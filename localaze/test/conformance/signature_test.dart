/// Conformance group: signature. Contract section 4.
///
/// The group that matters most. The first implementation compared parameter
/// names only, which accepts a retype, and a retype is the likelier edit.
library;

import 'package:localaze/localaze.dart';
import 'package:test/test.dart';

import '../fakes/fakes.dart';
import '../fakes/fixture_project.dart';

LocalazeCatalog parse(String path) => LocalazeCatalog.parse(fixture(path))!;

void main() {
  final signature = fixtureSignature;

  test('accepts the catalog it was generated from', () {
    expect(signature.incompatibilities(parse('catalogs/ru.json')), isEmpty);
  });

  test('signature.retyped-parameter-refused', () {
    // 1.0.2 is a patch, so policy accepts it. Every key is present, so a
    // key-set check accepts it. inbox.unread still declares a parameter named
    // "count", so a name-only check accepts it too.
    //
    // The type changed from NUMBER to STRING. Generated code has already
    // promised every call site inboxUnread(count: num). This is the case that
    // the name-only implementation gets wrong.
    final problems =
        signature.incompatibilities(parse('updates/retyped-1.0.2-ru.json'));

    expect(problems, isNotEmpty);
    expect(problems.single, contains('inbox.unread.count'));
    expect(problems.single, contains('now string'));
    expect(problems.single, contains('generated as number'));
  });

  test('a name-only check would have accepted it — proving the case is real', () {
    // Reproduces the old logic against the same fixture. If this ever fails,
    // the fixture stopped exercising the bug and the test above is hollow.
    final catalog = parse('updates/retyped-1.0.2-ru.json');
    final namesOnly = <String>[];

    for (final entry in signature.keys.entries) {
      final message = catalog.messages[entry.key];
      if (message == null) {
        namesOnly.add('missing ${entry.key}');
        continue;
      }
      final declared = message.params.map((p) => p.name).toSet();
      for (final expected in entry.value) {
        if (!declared.contains(expected.name)) {
          namesOnly.add('${entry.key} lost ${expected.name}');
        }
      }
    }
    expect(namesOnly, isEmpty,
        reason: 'the name-only check finds nothing wrong, which is the defect');
  });

  test('signature.missing-key-refused', () {
    final problems =
        signature.incompatibilities(parse('updates/major-2.0.0-ru.json'));

    expect(problems, contains('auth.sign_out is missing'));
  });

  test('signature.added-key-ignored', () {
    // minor-1.1.0 adds settings.title, which no accessor references. A newer
    // platform release is not a client failure.
    final catalog = parse('updates/minor-1.1.0-ru.json');

    expect(signature.incompatibilities(catalog), isEmpty);
    expect(catalog.messages.containsKey('settings.title'), isTrue);
    expect(signature.keys.containsKey('settings.title'), isFalse);
  });

  test('signature.extra-parameter-ignored', () {
    // The signature is a floor, not an equality.
    const body = '''
    {"version":"1.0.1","messages":{
      "auth.sign_out":{"selectors":[],"params":[],"variants":{"*":[{"text":"x"}]}},
      "auth.welcome":{"selectors":[],"params":[
        {"name":"name","type":"STRING"},{"name":"extra","type":"NUMBER"}],
        "variants":{"*":[{"text":"hi "},{"var":"name","type":"STRING"}]}},
      "billing.due":{"selectors":[],"params":[{"name":"when","type":"DATETIME"}],
        "variants":{"*":[{"var":"when","type":"DATETIME"}]}},
      "inbox.unread":{"selectors":["count"],"params":[{"name":"count","type":"NUMBER"}],
        "variants":{"*":[{"var":"count","type":"NUMBER"}]}}}}''';

    expect(signature.incompatibilities(LocalazeCatalog.parse(body)!), isEmpty);
  });

  test('a renamed parameter is refused', () {
    const body = '''
    {"version":"1.0.1","messages":{
      "auth.sign_out":{"selectors":[],"params":[],"variants":{"*":[{"text":"x"}]}},
      "auth.welcome":{"selectors":[],"params":[{"name":"username","type":"STRING"}],
        "variants":{"*":[{"var":"username","type":"STRING"}]}},
      "billing.due":{"selectors":[],"params":[{"name":"when","type":"DATETIME"}],
        "variants":{"*":[{"var":"when","type":"DATETIME"}]}},
      "inbox.unread":{"selectors":["count"],"params":[{"name":"count","type":"NUMBER"}],
        "variants":{"*":[{"var":"count","type":"NUMBER"}]}}}}''';

    expect(signature.incompatibilities(LocalazeCatalog.parse(body)!).single,
        contains('no longer takes "name"'));
  });

  test('signature.refusal-is-whole', () async {
    // One key of four is incompatible. None of the four may be applied — half
    // an update means some screens render text the compiler never checked.
    final reported = Reported();
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.2')),
      '/translations': ok(fixture('updates/retyped-1.0.2-ru.json')),
    });

    final runtime = runtimeFor('ru',
        config: LocalazeConfig(
          apiKey: 'k',
          applyImmediately: true,
          transport: transport,
          onDiagnostic: reported.call,
        ));

    final status = await runtime.update();

    expect(status.outcome, LocalazeFetchOutcome.refusedBySignature);
    // auth.sign_out is identical in the refused catalog, and still must not be
    // taken from it.
    expect(runtime.render('auth.sign_out'), 'Выход');
    expect(runtime.version, '1.0.0');
  });

  test('signature.rechecked-after-upgrade', () async {
    // A cached catalog written before the app upgraded, next to code that now
    // promises something else. It must be dropped on load, not trusted.
    final reported = Reported();
    final storage = FakeStorage(cache: fixture('updates/retyped-1.0.2-ru.json'));

    final runtime = runtimeFor('ru',
        config: LocalazeConfig(
          apiKey: 'k',
          storage: storage,
          onDiagnostic: reported.call,
        ));

    await runtime.load();

    expect(runtime.render('inbox.unread', args: {'count': 5}, selector: 5),
        'У вас 5 сообщений');
    expect(reported.mentions('Dropping the cached ru catalog'), isTrue);
  });
}
