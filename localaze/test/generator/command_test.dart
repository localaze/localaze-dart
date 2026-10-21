/// `bin/generate.dart` as a build runs it: a real process, real files.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const String _fixtures = '../contract/fixtures';

Future<ProcessResult> _generate(List<String> arguments) => Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/generate.dart', ...arguments],
    );

void main() {
  late Directory out;

  setUp(() => out = Directory.systemTemp.createTempSync('localaze-gen-'));
  tearDown(() => out.deleteSync(recursive: true));

  test('writes the golden source and every catalog', () async {
    final result = await _generate(<String>[
      '--manifest', '$_fixtures/manifest.json',
      '--catalogs', '$_fixtures/catalogs',
      '--out', '${out.path}/lib/localaze.g.dart',
      '--assets', '${out.path}/assets/localaze',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File('${out.path}/lib/localaze.g.dart').readAsStringSync(),
        File('test/generator/golden/localaze.g.dart').readAsStringSync());
    for (final language in <String>['az', 'ru']) {
      expect(
          File('${out.path}/assets/localaze/$language.json').readAsStringSync(),
          File('$_fixtures/catalogs/$language.json').readAsStringSync());
    }
  });

  test('a failure exits 1, names the problem and writes nothing', () async {
    final catalogs = Directory('${out.path}/only-az')..createSync();
    File('$_fixtures/catalogs/az.json').copySync('${catalogs.path}/az.json');

    final result = await _generate(<String>[
      '--manifest', '$_fixtures/manifest.json',
      '--catalogs', catalogs.path,
      '--out', '${out.path}/lib/localaze.g.dart',
      '--assets', '${out.path}/assets/localaze',
    ]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('No catalog for language "ru".'));
    expect(File('${out.path}/lib/localaze.g.dart').existsSync(), isFalse);
    expect(Directory('${out.path}/assets').existsSync(), isFalse);
  });

  test('a usage error exits 64 and prints the usage', () async {
    final result = await _generate(<String>['--nonsense']);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Unknown option "--nonsense"'));
  });

  test('an unreachable server is a failure, not a crash', () async {
    final result = await _generate(<String>[
      '--key', 'k',
      '--base-url', 'http://127.0.0.1:9',
      '--out', '${out.path}/lib/localaze.g.dart',
      '--assets', '${out.path}/assets/localaze',
    ]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Could not reach http://127.0.0.1:9'));
  });

  group('online', () {
    late HttpServer server;
    final requests = <Uri>[];
    var manifestStatus = 200;

    setUp(() async {
      requests.clear();
      manifestStatus = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request.uri);
        final response = request.response;
        if (request.headers.value('X-Localaze-Key') != 'good-key') {
          response.statusCode = 401;
          response.write(jsonEncode({'detail': 'A valid key is required.'}));
        } else if (request.uri.path == '/api/v1/read/manifest') {
          response.statusCode = manifestStatus;
          response.write(manifestStatus == 200
              ? File('$_fixtures/manifest.json').readAsStringSync()
              : jsonEncode({
                  'detail': 'Release 1.0.0 cannot back generated code.',
                  'gaps': ['inbox.unread is missing in az'],
                }));
        } else {
          final language = request.uri.pathSegments.last;
          response.write(
              File('$_fixtures/catalogs/$language.json').readAsStringSync());
        }
        await response.close();
      });
    });

    tearDown(() => server.close(force: true));

    List<String> arguments(String key) => <String>[
          '--key', key,
          '--base-url', 'http://127.0.0.1:${server.port}',
          '--out', '${out.path}/lib/localaze.g.dart',
          '--assets', '${out.path}/assets/localaze',
        ];

    test('fetches the manifest, then catalogs pinned to its version', () async {
      final result = await _generate(arguments('good-key'));

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('${out.path}/lib/localaze.g.dart').readAsStringSync(),
          File('test/generator/golden/localaze.g.dart').readAsStringSync());

      expect(requests.first.path, '/api/v1/read/manifest');
      expect(requests.first.queryParameters['strict'], 'true');
      final catalogs = requests.skip(1).toList();
      expect(catalogs.map((uri) => uri.path), <String>[
        '/api/v1/read/translations/az',
        '/api/v1/read/translations/ru',
      ]);
      for (final uri in catalogs) {
        expect(uri.queryParameters,
            <String, String>{'format': 'resolved', 'version': '1.0.0'});
      }
    });

    test('a wrong key says so', () async {
      final result = await _generate(arguments('wrong-key'));

      expect(result.exitCode, 1);
      expect(result.stderr, contains('returned 401'));
      expect(result.stderr, contains('Check the integration key.'));
    });

    test('a refused release prints every gap the server named', () async {
      manifestStatus = 422;
      final result = await _generate(arguments('good-key'));

      expect(result.exitCode, 1);
      expect(result.stderr, contains('returned 422'));
      expect(result.stderr, contains('inbox.unread is missing in az'));
      expect(File('${out.path}/lib/localaze.g.dart').existsSync(), isFalse);
    });
  });
}
