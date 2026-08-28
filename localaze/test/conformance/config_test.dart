/// Conformance group: config. Contract section 9.
library;

import 'package:localaze/localaze.dart';
import 'package:test/test.dart';

import '../fakes/fakes.dart';
import '../fakes/fixture_project.dart';

void main() {
  test('config.key-only-works', () {
    // An app constructing the SDK with only a key must behave sensibly. Every
    // other option takes its documented default.
    const config = LocalazeConfig(apiKey: 'k');

    expect(config.baseUrl, 'https://localize.sharpy.dev');
    expect(config.policy, LocalazeUpdatePolicy.minorAndPatch);
    expect(config.timeout, const Duration(seconds: 10));
    expect(config.applyImmediately, isFalse);
    expect(config.dateFormatter, localazeIsoUtc);
    expect(config.onDiagnostic, isNull);
    expect(config.transport, isNull);
    expect(config.storage, isNull);

    final runtime = runtimeFor('ru', config: config);
    expect(runtime.render('auth.sign_out'), 'Выход');
    expect(runtime.version, '1.0.0');
  });

  test('config.apply-immediately-off-by-default', () async {
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(fixture('updates/patch-1.0.1-ru.json')),
    });

    final runtime = runtimeFor('ru',
        config: LocalazeConfig(apiKey: 'k', transport: transport));

    final status = await runtime.update();

    expect(status.outcome, LocalazeFetchOutcome.applied);
    // Text changing under a user mid-session is worse than text being one
    // launch out of date.
    expect(runtime.render('auth.sign_out'), 'Выход');
  });

  test('config.version-in-use-readable', () async {
    final transport = FakeTransport({
      '/version': ok(versionBody('1.0.1')),
      '/translations': ok(fixture('updates/patch-1.0.1-ru.json')),
    });

    final runtime = runtimeFor('ru',
        config: LocalazeConfig(
            apiKey: 'k', applyImmediately: true, transport: transport));

    expect(runtime.version, '1.0.0');
    await runtime.update();
    expect(runtime.version, '1.0.1');
  });

  test('a custom baseUrl is honoured', () async {
    final transport = FakeTransport({'/version': ok(versionBody('1.0.1'))});

    await runtimeFor('ru',
            config: LocalazeConfig(
                apiKey: 'k',
                baseUrl: 'https://staging.localaze.internal',
                transport: transport))
        .update();

    expect(transport.urls.first, startsWith('https://staging.localaze.internal'));
  });

  test('LocalazeNoStorage is the documented no-persistence default', () async {
    const storage = LocalazeNoStorage();

    expect(await storage.readAsset('ru'), isNull);
    expect(await storage.readCache('ru'), isNull);
    expect(await storage.writeCache('ru', '{}'), isFalse);
  });
}
