/// Conformance group: resolution. Contract section 7.
library;

import 'package:localaze/localaze.dart';
import 'package:test/test.dart';

import '../fakes/fakes.dart';
import '../fakes/fixture_project.dart';

/// A minimal ru catalog whose auth.sign_out reads [text].
String catalogSaying(String text, String version) => '''
{"version":"$version","language":"ru","messages":{
  "auth.sign_out":{"selectors":[],"params":[],"variants":{"*":[{"text":"$text"}]}},
  "auth.welcome":{"selectors":[],"params":[{"name":"name","type":"STRING"}],
    "variants":{"*":[{"text":"hi "},{"var":"name","type":"STRING"}]}},
  "billing.due":{"selectors":[],"params":[{"name":"when","type":"DATETIME"}],
    "variants":{"*":[{"var":"when","type":"DATETIME"}]}},
  "inbox.unread":{"selectors":["count"],"params":[{"name":"count","type":"NUMBER"}],
    "variants":{"*":[{"var":"count","type":"NUMBER"}]}}}}''';

void main() {
  test('resolution.applied-over-cached-over-bundled', () async {
    final storage = FakeStorage(
      asset: catalogSaying('from-bundled', '1.0.0'),
      cache: catalogSaying('from-cached', '1.0.0'),
    );
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(catalogSaying('from-applied', '1.0.1')),
    });

    final runtime = runtimeFor('ru',
        compiledIn: catalogSaying('from-compiled-in', '1.0.0'),
        config: LocalazeConfig(
          apiKey: 'k',
          applyImmediately: true,
          transport: transport,
          storage: storage,
        ));

    // Level 4 only.
    expect(runtime.render('auth.sign_out'), 'from-compiled-in');

    await runtime.load();
    expect(runtime.render('auth.sign_out'), 'from-cached');

    await runtime.update();
    expect(runtime.render('auth.sign_out'), 'from-applied');
  });

  test('bundled beats compiled-in when there is no cache', () async {
    final storage = FakeStorage(asset: catalogSaying('from-bundled', '1.0.0'));
    final runtime = runtimeFor('ru',
        compiledIn: catalogSaying('from-compiled-in', '1.0.0'),
        config: LocalazeConfig(apiKey: 'k', storage: storage));

    await runtime.load();
    expect(runtime.render('auth.sign_out'), 'from-bundled');
  });

  test('resolution.per-key-fallback', () async {
    // partial-ru.json omits billing.due. The three keys it has come from the
    // asset; the missing one falls through to the compiled-in copy. Per key,
    // not per catalog — one gap must not cost an app every string it has.
    final storage = FakeStorage(asset: fixture('bundled/partial-ru.json'));

    final runtime = runtimeFor('ru',
        config: LocalazeConfig(apiKey: 'k', storage: storage));

    await runtime.load();

    expect(runtime.render('auth.sign_out'), 'Выход');
    expect(
        runtime.render('billing.due', args: {'when': DateTime.utc(2026, 3, 1)}),
        'Оплата до 2026-03-01T00:00:00Z');
  });

  test('resolution.cache-survives-launch', () async {
    // One run applies and persists; a fresh runtime over the same storage picks
    // it up ahead of the bundled copy.
    final storage = FakeStorage(asset: catalogSaying('from-bundled', '1.0.0'));
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(catalogSaying('from-applied', '1.0.1')),
    });

    final first = runtimeFor('ru',
        compiledIn: catalogSaying('compiled', '1.0.0'),
        config: LocalazeConfig(
            apiKey: 'k',
            applyImmediately: true,
            transport: transport,
            storage: storage));
    await first.load();
    await first.update();

    final relaunched = runtimeFor('ru',
        compiledIn: catalogSaying('compiled', '1.0.0'),
        config: LocalazeConfig(apiKey: 'k', storage: storage));
    await relaunched.load();

    expect(relaunched.render('auth.sign_out'), 'from-applied');
    expect(relaunched.version, '1.0.1');
  });

  test('resolution.no-cache-directory-is-session-only', () async {
    // The Dart default. Not an error: this package has no dependency that can
    // find a writable directory on its own.
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(catalogSaying('from-applied', '1.0.1')),
    });
    final config = LocalazeConfig(
        apiKey: 'k', applyImmediately: true, transport: transport);

    final session = runtimeFor('ru',
        compiledIn: catalogSaying('compiled', '1.0.0'), config: config);
    final status = await session.update();

    expect(status.outcome, LocalazeFetchOutcome.applied);
    expect(status.detail, contains('this session only'));
    expect(session.render('auth.sign_out'), 'from-applied');

    final relaunched = runtimeFor('ru',
        compiledIn: catalogSaying('compiled', '1.0.0'), config: config);
    await relaunched.load();
    expect(relaunched.render('auth.sign_out'), 'compiled');
  });

  test('resolution.offline-first-launch', () async {
    // Fresh install, no network, no cache. Every key still renders, and no
    // request is made at all.
    final transport = FakeTransport(const {});
    final runtime = runtimeFor('ru',
        config: LocalazeConfig(apiKey: 'k', transport: transport));

    expect(runtime.render('auth.sign_out'), 'Выход');
    expect(runtime.render('auth.welcome', args: {'name': 'Аян'}),
        'Добро пожаловать, Аян');
    expect(runtime.render('inbox.unread', args: {'count': 11}, selector: 11),
        'У вас 11 сообщений');
    expect(transport.urls, isEmpty);
  });

  test('applyImmediately off holds the catalog until asked', () async {
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(catalogSaying('from-applied', '1.0.1')),
    });

    final runtime = runtimeFor('ru',
        compiledIn: catalogSaying('compiled', '1.0.0'),
        config: LocalazeConfig(apiKey: 'k', transport: transport));

    await runtime.update();
    expect(runtime.render('auth.sign_out'), 'compiled',
        reason: 'text must not change under a user mid-session');

    expect(runtime.applyPending(), isTrue);
    expect(runtime.render('auth.sign_out'), 'from-applied');
    expect(runtime.applyPending(), isFalse);
  });
}
