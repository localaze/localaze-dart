/// Conformance group: fetch. Contract section 6.
library;

import 'package:localaze/localaze.dart';
import 'package:test/test.dart';

import '../fakes/fakes.dart';
import '../fakes/fixture_project.dart';

LocalazeRuntime runtimeWith(
  FakeTransport transport, {
  FakeStorage? storage,
  Reported? reported,
  LocalazeUpdatePolicy policy = LocalazeUpdatePolicy.minorAndPatch,
  bool applyImmediately = true,
}) {
  return runtimeFor('ru',
      config: LocalazeConfig(
        apiKey: 'test-key',
        policy: policy,
        applyImmediately: applyImmediately,
        transport: transport,
        storage: storage,
        onDiagnostic: reported?.call,
      ));
}

void main() {
  test('fetch.sends-api-key', () async {
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(fixture('updates/patch-1.0.1-ru.json')),
    });

    await runtimeWith(transport).update();

    expect(transport.headers, isNotEmpty);
    for (final headers in transport.headers) {
      expect(headers['X-Localaze-Key'], 'test-key');
    }
    // The key carries the project and the environment, so neither appears in
    // any URL. A staging build cannot read production by editing a parameter.
    for (final url in transport.urls) {
      expect(url, isNot(contains('project')));
      expect(url, isNot(contains('environment')));
    }
  });

  test('fetch.sends-if-none-match', () async {
    // Not done by the implementation this replaces, though the server has
    // served version-scoped ETags all along.
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations':
          ok(fixture('updates/patch-1.0.1-ru.json'), etag: '"1.0.1-ab"'),
    });
    final runtime = runtimeWith(transport);

    await runtime.update();
    expect(transport.headerValue('If-None-Match'), isNull,
        reason: 'nothing is held before the first fetch');

    transport.headers.clear();
    transport.responses['/version'] = ok(versionBody('1.0.2'));
    await runtime.update();

    expect(transport.headerValue('If-None-Match'), '"1.0.1-ab"');
  });

  test('fetch.304-keeps-content', () async {
    final reported = Reported();
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': const LocalazeResponse(status: 304, etag: '"1.0.1-ab"'),
    });
    final runtime = runtimeWith(transport, reported: reported);

    final status = await runtime.update();

    // A success, not a failure. This is the cheap path the ETag exists for.
    expect(status.outcome, LocalazeFetchOutcome.upToDate);
    expect(runtime.render('auth.sign_out'), 'Выход');
    expect(reported.isEmpty, isTrue,
        reason: '304 is not something to report as a problem');
  });

  test('fetch.pinned-version', () async {
    final transport = FakeTransport({
      '/translations': ok(fixture('updates/patch-1.0.1-ru.json')),
    });

    final status = await runtimeWith(transport).update(pinnedVersion: '1.0.1');

    expect(status.outcome, LocalazeFetchOutcome.applied);
    expect(transport.urls.single, contains('version=1.0.1'));
    expect(transport.urls.single, contains('format=resolved'));
    // A pin answers the version question, so the version endpoint is not hit.
    expect(transport.urls.where((u) => u.contains('/read/version')), isEmpty);
  });

  test('fetch.nothing-written-before-signature-passes', () async {
    final storage = FakeStorage();
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.2')),
      '/translations': ok(fixture('updates/retyped-1.0.2-ru.json')),
    });

    final status = await runtimeWith(transport, storage: storage).update();

    expect(status.outcome, LocalazeFetchOutcome.refusedBySignature);
    expect(storage.writes, 0, reason: 'a refused catalog must leave no trace');
    expect(storage.cache, isNull);
  });

  test('the order is policy, version, download, signature, persist', () async {
    // policy none short-circuits before the transport is touched at all.
    final transport = FakeTransport({'/version': ok(versionBody('1.0.1'))});

    await runtimeWith(transport, policy: LocalazeUpdatePolicy.none).update();
    expect(transport.urls, isEmpty);

    // A version the policy refuses stops before the catalog is downloaded.
    final second = FakeTransport({
      '/version': ok(versionBody('1.1.0')),
      '/translations': ok(fixture('updates/minor-1.1.0-ru.json')),
    });
    await runtimeWith(second, policy: LocalazeUpdatePolicy.patchOnly).update();

    expect(second.urls.length, 1);
    expect(second.urls.single, contains('/read/version'));
  });

  test('an applied catalog is persisted', () async {
    final storage = FakeStorage();
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(fixture('updates/patch-1.0.1-ru.json')),
    });

    await runtimeWith(transport, storage: storage).update();

    expect(storage.writes, 1);
    expect(storage.cache, contains('Выйти'));
  });

  test('a patch changes the wording without regenerating anything', () async {
    // The outcome the whole design exists for: a typo fix reaching a running
    // app with no rebuild and no new generated source.
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(fixture('updates/patch-1.0.1-ru.json')),
    });
    final runtime = runtimeWith(transport);

    expect(runtime.render('auth.sign_out'), 'Выход');
    await runtime.update();
    expect(runtime.render('auth.sign_out'), 'Выйти');
    expect(runtime.version, '1.0.1');
  });
}
