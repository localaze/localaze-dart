/// The generator against the shared fixture project.
///
/// See `contract/generator-contract.md` §9 and the `generator` group of
/// `contract/conformance.json`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:localaze/src/generator/dart_emitter.dart';
import 'package:localaze/src/generator/plan.dart';
import 'package:test/test.dart';

import '../fakes/fakes.dart';

const String _golden = 'test/generator/golden/localaze.g.dart';

Map<String, String> _catalogs() => <String, String>{
      'az': fixture('catalogs/az.json'),
      'ru': fixture('catalogs/ru.json'),
    };

Map<String, Object?> _manifest() =>
    jsonDecode(fixture('manifest.json')) as Map<String, Object?>;

PlanResult _plan({
  Map<String, Object?>? manifest,
  Map<String, String>? catalogs,
  bool allowGaps = false,
}) =>
    plan(
      manifest: jsonEncode(manifest ?? _manifest()),
      catalogs: catalogs ?? _catalogs(),
      allowGaps: allowGaps,
    );

/// The fixture manifest with one key's entry replaced or added.
Map<String, Object?> _withKey(Map<String, Object?> entry) {
  final manifest = _manifest();
  final keys = (manifest['keys'] as List).cast<Map<String, Object?>>().toList()
    ..add(entry);
  return manifest..['keys'] = keys;
}

/// A catalog with [key] added to its messages.
String _catalogWith(String language, String key, Map<String, Object?> message) {
  final catalog =
      jsonDecode(fixture('catalogs/$language.json')) as Map<String, Object?>;
  (catalog['messages'] as Map<String, Object?>)[key] = message;
  return jsonEncode(catalog);
}

const Map<String, Object?> _simple = <String, Object?>{
  'selectors': <String>[],
  'params': <Object>[],
  'variants': <String, Object?>{
    '*': <Object>[
      <String, String>{'text': 'x'},
    ],
  },
};

void main() {
  test('generator.golden — output is byte-identical to the checked-in file',
      () {
    final result = _plan();
    expect(result.problems, isEmpty);
    final source = emitDart(result.plan!);

    // UPDATE_GOLDEN=1 rewrites the file. The diff is then reviewed like any
    // other change, which is the point of a golden.
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      File(_golden).writeAsStringSync(source);
    }
    expect(source, File(_golden).readAsStringSync());
  });

  test('generator.golden — the same input generates the same output twice',
      () {
    expect(emitDart(_plan().plan!), emitDart(_plan().plan!));
  });

  test('generator.catalogs-written — catalogs are carried byte for byte', () {
    final planned = _plan().plan!;
    expect(planned.catalogs, _catalogs());
    expect(planned.languages, <String>['az', 'ru']);
  });

  test('generator.missing-catalog', () {
    final result = _plan(catalogs: {'az': fixture('catalogs/az.json')});
    expect(result.plan, isNull);
    expect(result.problems, contains('No catalog for language "ru".'));
  });

  test('generator.missing-key — a gap fails generation', () {
    final ru = jsonDecode(fixture('catalogs/ru.json')) as Map<String, Object?>;
    (ru['messages'] as Map).remove('auth.sign_out');
    final result = _plan(catalogs: {..._catalogs(), 'ru': jsonEncode(ru)});

    expect(result.plan, isNull);
    expect(result.problems, contains('auth.sign_out is missing in ru.'));
  });

  test('generator.allow-gaps — the same gap is a warning', () {
    final ru = jsonDecode(fixture('catalogs/ru.json')) as Map<String, Object?>;
    (ru['messages'] as Map).remove('auth.sign_out');
    final result = _plan(
        catalogs: {..._catalogs(), 'ru': jsonEncode(ru)}, allowGaps: true);

    expect(result.plan, isNotNull);
    expect(result.warnings, contains('auth.sign_out is missing in ru.'));
  });

  test('generator.version-mismatch', () {
    final ru = jsonDecode(fixture('catalogs/ru.json')) as Map<String, Object?>;
    ru['version'] = '1.0.1';
    final result = _plan(catalogs: {..._catalogs(), 'ru': jsonEncode(ru)});

    expect(result.plan, isNull);
    expect(result.problems,
        contains('The "ru" catalog is version 1.0.1, but the manifest is 1.0.0.'));
  });

  test('generator.unsupported-operand', () {
    final manifest = _manifest();
    (manifest['pluralRules'] as Map)['ru'] = {'one': 'f == 1'};
    final result = _plan(manifest: manifest);

    expect(result.plan, isNull);
    expect(result.problems.single, contains('uses f'));
  });

  test('generator.unrecognised-rule — nothing but the operator set compiles',
      () {
    final manifest = _manifest();
    (manifest['pluralRules'] as Map)['ru'] = {'one': 'n == 1; exit(0)'};
    final result = _plan(manifest: manifest);

    expect(result.plan, isNull);
    expect(result.problems.single, contains('exit'));
  });

  test('generator.accessor-collision', () {
    final manifest = _manifest();
    manifest['keys'] = <Object>[
      {'key': 'a.b_c', 'params': <Object>[], 'selects': false},
      {'key': 'a_b.c', 'params': <Object>[], 'selects': false},
    ];
    final result = _plan(manifest: manifest, catalogs: {
      'az': _catalogWith('az', 'a_b.c', _simple),
      'ru': _catalogWith('ru', 'a_b.c', _simple),
    }, allowGaps: true);

    expect(result.plan, isNull);
    expect(result.problems,
        contains('Keys "a.b_c" and "a_b.c" both generate the accessor "aBC".'));
  });

  test('generator.reserved-member', () {
    final result = _plan(
      manifest: _withKey({'key': 'runtime', 'params': <Object>[], 'selects': false}),
      catalogs: {
        'az': _catalogWith('az', 'runtime', _simple),
        'ru': _catalogWith('ru', 'runtime', _simple),
      },
    );

    expect(result.plan, isNull);
    expect(result.problems.single, contains('"runtime", which is reserved'));
  });

  test('generator.non-number-selector', () {
    const message = <String, Object?>{
      'selectors': <String>['who'],
      'params': <Object>[
        {'name': 'who', 'type': 'STRING'},
      ],
      'variants': <String, Object?>{
        '*': <Object>[
          {'var': 'who', 'type': 'STRING'},
        ],
      },
    };
    final result = _plan(
      manifest: _withKey({
        'key': 'greeting',
        'params': [
          {'name': 'who', 'type': 'STRING'},
        ],
        'selects': true,
      }),
      catalogs: {
        'az': _catalogWith('az', 'greeting', message),
        'ru': _catalogWith('ru', 'greeting', message),
      },
    );

    expect(result.plan, isNull);
    expect(result.problems.single, contains(r'selects on $who, a STRING'));
  });

  test('generator.all-problems-reported — every problem, not the first', () {
    final manifest = _manifest();
    (manifest['pluralRules'] as Map)['ru'] = {'one': 't == 1'};
    final result = _plan(
      manifest: manifest,
      catalogs: {'az': fixture('catalogs/az.json')},
    );

    expect(result.problems, hasLength(2));
  });

  test('a reserved Dart word takes a trailing underscore', () {
    const message = <String, Object?>{
      'selectors': <String>[],
      'params': <Object>[
        {'name': 'in', 'type': 'STRING'},
      ],
      'variants': <String, Object?>{
        '*': <Object>[
          {'var': 'in', 'type': 'STRING'},
        ],
      },
    };
    final result = _plan(
      manifest: _withKey({
        'key': 'default',
        'params': [
          {'name': 'in', 'type': 'STRING'},
        ],
        'selects': false,
      }),
      catalogs: {
        'az': _catalogWith('az', 'default', message),
        'ru': _catalogWith('ru', 'default', message),
      },
    );

    final source = emitDart(result.plan!);
    expect(source, contains(r"String default_({required String in_})"));
    expect(source, contains(r"'in': in_"));
  });
}
