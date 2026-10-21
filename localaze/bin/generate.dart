/// `dart run localaze:generate` — the typed source and catalogs for one
/// published release.
///
/// See `contract/generator-contract.md`. This file is the only part of the
/// generator that touches the network or the filesystem; the decisions are in
/// `lib/src/generator/`, where the tests reach them without either.
library;

import 'dart:convert';
import 'dart:io';

import 'package:localaze/src/generator/dart_emitter.dart';
import 'package:localaze/src/generator/plan.dart';

const String _usage = '''
Generates typed Localaze translations for one published release.

Usage:
  dart run localaze:generate --key <integration key> --version <x.y.z>
  dart run localaze:generate --manifest <file> --catalogs <dir>

Options:
  --key          Integration key. Carries the project and the environment.
  --version      Release to generate from. A build should pin it.
                 Omitted means the environment's live release.
  --base-url     Default https://localize.sharpy.dev
  --out          Generated file. Default lib/localaze.g.dart
  --assets       Catalog directory. Default assets/localaze
  --allow-gaps   Generate even when a translation is missing.
  --manifest     Read the manifest from a file instead of the server.
  --catalogs     Read <language>.json catalogs from a directory.
  --help         Show this text.
''';

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments);
}

/// Runs the generator and returns the process exit code.
Future<int> run(List<String> arguments) async {
  final Map<String, String?> options;
  try {
    options = _parse(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln('error: ${error.message}')
      ..writeln()
      ..write(_usage);
    return 64;
  }

  if (options.containsKey('help')) {
    stdout.write(_usage);
    return 0;
  }

  final offline = options['manifest'] != null || options['catalogs'] != null;
  if (offline && (options['manifest'] == null || options['catalogs'] == null)) {
    stderr.writeln('error: --manifest and --catalogs go together.');
    return 64;
  }
  if (!offline && (options['key'] ?? '').isEmpty) {
    stderr.writeln('error: --key is required, or --manifest with --catalogs.');
    return 64;
  }

  final allowGaps = options.containsKey('allow-gaps');
  final inputs = offline
      ? _readOffline(options['manifest']!, options['catalogs']!)
      : await _fetch(
          options['key']!,
          options['version'],
          options['base-url'] ?? 'https://localize.sharpy.dev',
          allowGaps,
        );
  if (inputs.problems.isNotEmpty) return _fail(inputs.problems);

  final result = plan(
    manifest: inputs.manifest!,
    catalogs: inputs.catalogs,
    allowGaps: allowGaps,
  );
  for (final warning in result.warnings) {
    stderr.writeln('warning: $warning');
  }
  final planned = result.plan;
  if (planned == null) return _fail(result.problems);

  final out = options['out'] ?? 'lib/localaze.g.dart';
  final assets = options['assets'] ?? 'assets/localaze';
  try {
    _write(File(out), emitDart(planned));
    for (final language in planned.languages) {
      _write(File('$assets/$language.json'), planned.catalogs[language]!);
    }
  } on FileSystemException catch (error) {
    return _fail(<String>['Could not write ${error.path}: ${error.message}']);
  }

  stdout.writeln('Generated $out from ${planned.version} '
      '(${planned.environment}): ${planned.keys.length} keys, '
      '${planned.languages.length} languages. Catalogs in $assets/.');
  return 0;
}

int _fail(List<String> problems) {
  stderr.writeln('Generation failed:');
  for (final problem in problems) {
    stderr.writeln('  - $problem');
  }
  return 1;
}

void _write(File file, String content) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

const Set<String> _flags = <String>{'allow-gaps', 'help'};
const Set<String> _valued = <String>{
  'key', 'version', 'base-url', 'out', 'assets', 'manifest', 'catalogs',
};

Map<String, String?> _parse(List<String> arguments) {
  final options = <String, String?>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--')) {
      throw FormatException('Unexpected argument "$argument".');
    }
    final equals = argument.indexOf('=');
    final name = argument.substring(2, equals < 0 ? null : equals);
    if (_flags.contains(name)) {
      options[name] = null;
    } else if (_valued.contains(name)) {
      if (equals >= 0) {
        options[name] = argument.substring(equals + 1);
      } else if (index + 1 < arguments.length) {
        options[name] = arguments[++index];
      } else {
        throw FormatException('--$name needs a value.');
      }
    } else {
      throw FormatException('Unknown option "--$name".');
    }
  }
  return options;
}

final class _Inputs {
  _Inputs(this.manifest, this.catalogs, this.problems);

  final String? manifest;
  final Map<String, String> catalogs;
  final List<String> problems;
}

_Inputs _readOffline(String manifestPath, String catalogsPath) {
  final problems = <String>[];
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    return _Inputs(null, const {}, <String>['No manifest at $manifestPath.']);
  }
  final manifest = manifestFile.readAsStringSync();

  // Every language the manifest names, read if present. A missing one is the
  // plan's to report, alongside every other problem.
  final catalogs = <String, String>{};
  final directory = Directory(catalogsPath);
  if (!directory.existsSync()) {
    problems.add('No catalog directory at $catalogsPath.');
  } else {
    for (final entity in directory.listSync()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File && name.endsWith('.json')) {
        catalogs[name.substring(0, name.length - 5)] =
            entity.readAsStringSync();
      }
    }
  }
  return _Inputs(manifest, catalogs, problems);
}

Future<_Inputs> _fetch(
  String key,
  String? version,
  String baseUrl,
  bool allowGaps,
) async {
  final base = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final manifest = await _get(client, key, Uri.parse('$base/api/v1/read/manifest')
        .replace(queryParameters: <String, String>{
      if (version != null && version.isNotEmpty) 'version': version,
      'strict': allowGaps ? 'false' : 'true',
    }));
    if (manifest.problems.isNotEmpty) {
      return _Inputs(null, const {}, manifest.problems);
    }

    final parsed = jsonDecode(manifest.body!) as Map<String, Object?>;
    final pinned = parsed['version'] as String;
    final languages = (parsed['languages'] as List).cast<String>();

    // Pinned to the version the manifest returned, even when the caller did
    // not pin: a release published between the two requests would otherwise
    // pair one version's manifest with another's catalogs.
    final catalogs = <String, String>{};
    final problems = <String>[];
    for (final language in languages) {
      final catalog = await _get(client, key,
          Uri.parse('$base/api/v1/read/translations/'
                  '${Uri.encodeComponent(language)}')
              .replace(queryParameters: <String, String>{
        'format': 'resolved',
        'version': pinned,
      }));
      problems.addAll(catalog.problems);
      if (catalog.body != null) catalogs[language] = catalog.body!;
    }
    return _Inputs(manifest.body, catalogs, problems);
  } on Object catch (error) {
    return _Inputs(null, const {}, <String>['Could not reach $base: $error']);
  } finally {
    client.close(force: true);
  }
}

final class _Response {
  _Response(this.body, this.problems);

  final String? body;
  final List<String> problems;
}

Future<_Response> _get(HttpClient client, String key, Uri uri) async {
  final request = await client.getUrl(uri);
  request.headers
    ..set('X-Localaze-Key', key)
    ..set(HttpHeaders.acceptHeader, 'application/json');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  if (response.statusCode == 200) return _Response(body, const <String>[]);
  return _Response(null, _problemsOf(uri, response.statusCode, body));
}

/// The server's RFC 9457 problem, read for its detail and any gaps.
List<String> _problemsOf(Uri uri, int status, String body) {
  final problems = <String>[];
  var detail = '';
  try {
    final problem = jsonDecode(body);
    if (problem is Map) {
      if (problem['detail'] is String) detail = ': ${problem['detail']}';
      final gaps = problem['gaps'];
      if (gaps is List) problems.addAll(gaps.map((gap) => '$gap'));
    }
  } on FormatException {
    // Not a problem document. The status alone says enough.
  }
  final hint = status == 401 || status == 403
      ? ' Check the integration key.'
      : '';
  problems.insert(0, '${uri.path} returned $status$detail$hint');
  return problems;
}
