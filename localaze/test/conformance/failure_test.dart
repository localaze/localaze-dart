/// Conformance group: failure. Contract section 8.
///
/// The rule this whole group serves: no public API throws. A translation
/// outage is a stale screen; an SDK that throws makes it a crash.
library;

import 'package:localaze/localaze.dart';
import 'package:test/test.dart';

import '../fakes/fakes.dart';
import '../fakes/fixture_project.dart';

LocalazeRuntime runtimeWith({
  FakeTransport? transport,
  FakeStorage? storage,
  Reported? reported,
  String? compiledIn,
}) {
  return runtimeFor('ru',
      compiledIn: compiledIn,
      config: LocalazeConfig(
        apiKey: 'k',
        applyImmediately: true,
        transport: transport,
        storage: storage,
        onDiagnostic: reported?.call,
      ));
}

void main() {
  test('failure.network-unreachable', () async {
    final reported = Reported();
    final transport = FakeTransport({
      '/version': const LocalazeResponse.failed('connection refused'),
    });

    final runtime = runtimeWith(transport: transport, reported: reported);
    final status = await runtime.update();

    expect(status.outcome, LocalazeFetchOutcome.failed);
    expect(runtime.render('auth.sign_out'), 'Выход');
    expect(reported.isEmpty, isFalse);
  });

  test('failure.timeout', () async {
    final reported = Reported();
    // A timeout reaches the updater the same way any other transport failure
    // does, which is the point of the transport returning rather than throwing.
    final transport = FakeTransport({
      '/version': LocalazeResponse.failed(
          Exception('operation timed out after 10s')),
    });

    final status =
        await runtimeWith(transport: transport, reported: reported).update();

    expect(status.outcome, LocalazeFetchOutcome.failed);
    expect(reported.isEmpty, isFalse);
  });

  group('failure.non-200', () {
    for (final status in [401, 403, 404, 500, 503]) {
      test('$status is reported with its status', () async {
        final reported = Reported();
        final transport = FakeTransport({
          '/version': ok(versionBody('1.0.1')),
          '/translations': LocalazeResponse(status: status),
        });

        final runtime =
            runtimeWith(transport: transport, reported: reported);
        final result = await runtime.update();

        expect(result.outcome, LocalazeFetchOutcome.failed);
        // A 401 is a wrong key and must be distinguishable from a quiet
        // network by whoever reads the log.
        expect(reported.mentions('$status'), isTrue);
        expect(runtime.render('auth.sign_out'), 'Выход');
      });
    }
  });

  test('failure.malformed-json', () async {
    final reported = Reported();
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(fixture('updates/malformed-syntax-ru.txt')),
    });

    final runtime = runtimeWith(transport: transport, reported: reported);
    final status = await runtime.update();

    expect(status.outcome, LocalazeFetchOutcome.failed);
    expect(runtime.render('auth.sign_out'), 'Выход');
  });

  test('failure.missing-messages', () async {
    final reported = Reported();
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.4')),
      '/translations': ok(fixture('updates/malformed-shape-ru.json')),
    });

    final runtime = runtimeWith(transport: transport, reported: reported);
    final status = await runtime.update();

    expect(status.outcome, LocalazeFetchOutcome.failed);
    expect(reported.mentions('no readable messages'), isTrue);
    expect(runtime.render('auth.sign_out'), 'Выход');
  });

  test('failure.corrupt-cache-ignored', () async {
    final reported = Reported();
    final storage = FakeStorage(cache: '{"messages": trunc');

    final runtime = runtimeWith(storage: storage, reported: reported);
    await runtime.load();

    expect(reported.mentions('unreadable cached ru catalog'), isTrue);
    expect(runtime.render('auth.sign_out'), 'Выход');
  });

  test('a storage that throws is caught', () async {
    final reported = Reported();
    final storage = FakeStorage()..throwOnRead = StateError('disk gone');

    // load() must not propagate. It is the first thing an app calls.
    await expectLater(
        runtimeWith(storage: storage, reported: reported).load(), completes);
  });

  test('failure.missing-asset', () async {
    // assetPath points nowhere. Every key still renders, from the compiled-in
    // copy. This is why a path typo is stale text and never a blank screen.
    final runtime = runtimeWith(storage: FakeStorage());
    await runtime.load();

    expect(runtime.render('auth.sign_out'), 'Выход');
    expect(runtime.render('inbox.unread', args: {'count': 2}, selector: 2),
        'У вас 2 сообщения');
  });

  test('failure.unwritable-cache', () async {
    final reported = Reported();
    final storage = FakeStorage(writable: false);
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(fixture('updates/patch-1.0.1-ru.json')),
    });

    final runtime = runtimeWith(
        transport: transport, storage: storage, reported: reported);
    final status = await runtime.update();

    // Applied, and reported as not persisted. Not an error.
    expect(status.outcome, LocalazeFetchOutcome.applied);
    expect(status.detail, contains('session only'));
    expect(runtime.render('auth.sign_out'), 'Выйти');
    expect(reported.mentions('Could not cache'), isTrue);
  });

  test('failure.throwing-diagnostic-caught', () async {
    // A broken diagnostic must not take the app with it.
    var called = 0;
    final runtime = runtimeFor('ru',
        config: LocalazeConfig(
          apiKey: 'k',
          transport: FakeTransport(
              {'/version': const LocalazeResponse.failed('nope')}),
          onDiagnostic: (message, error) {
            called++;
            throw StateError('the app\'s logger is broken');
          },
        ));

    await expectLater(runtime.update(), completes);
    expect(called, greaterThan(0));
    expect(runtime.render('auth.sign_out'), 'Выход');
  });

  test('a transport that throws is caught', () async {
    // Implementations must not throw, but one supplied by an app might.
    final reported = Reported();
    final transport = FakeTransport(const {})
      ..throwOnGet = StateError('bad transport');

    final runtime = runtimeWith(transport: transport, reported: reported);

    await expectLater(runtime.update(), completes);
    expect(reported.mentions('threw'), isTrue);
  });

  test('no transport configured is reported, not thrown', () async {
    final reported = Reported();
    final runtime = runtimeWith(reported: reported);

    final status = await runtime.update();

    expect(status.outcome, LocalazeFetchOutcome.failed);
    expect(reported.mentions('No transport configured'), isTrue);
  });

  test('an unreadable compiled-in catalog still leaves the app running', () {
    final reported = Reported();
    final runtime = runtimeWith(compiledIn: 'not json at all', reported: reported);

    // A generator bug, not a runtime condition. Failing soft keeps the no-throw
    // rule and renders key names, which is loud enough to notice.
    expect(runtime.render('auth.sign_out'), 'auth.sign_out');
    expect(reported.mentions('compiled-in ru catalog'), isTrue);
  });

  test('failure.last-status-readable', () async {
    final runtime = runtimeWith(
        transport: FakeTransport(
            {'/version': const LocalazeResponse.failed('down')}));

    expect(runtime.lastFetch.outcome, LocalazeFetchOutcome.none);

    await runtime.update();

    expect(runtime.lastFetch.outcome, LocalazeFetchOutcome.failed);
    expect(runtime.lastFetch.detail, isNotNull);
  });

  test('failure.no-public-api-throws — every failure at once', () async {
    // Everything wrong simultaneously: dead network, unreadable cache, no
    // asset, unwritable storage, throwing diagnostic.
    final storage = FakeStorage(cache: 'corrupt{', writable: false);
    final runtime = runtimeFor('ru',
        config: LocalazeConfig(
          apiKey: 'k',
          transport: FakeTransport(const {})..throwOnGet = 'boom',
          storage: storage,
          onDiagnostic: (m, e) => throw StateError('logger down'),
        ));

    await expectLater(runtime.load(), completes);
    await expectLater(runtime.update(), completes);
    expect(runtime.applyPending(), isFalse);
    expect(runtime.render('auth.sign_out'), 'Выход');
    expect(runtime.version, '1.0.0');
    expect(runtime.lastFetch.outcome, LocalazeFetchOutcome.failed);
  });
}
