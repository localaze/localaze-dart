/// Conformance group: purity. Contract sections 2, 3 and 10.
///
/// These assert on the source itself, because the properties are about what the
/// package does not contain. A runtime test cannot prove the absence of a CLDR
/// table or a stray dart:io import.
library;

import 'dart:io';

import 'package:test/test.dart';

/// Every `.dart` file under `lib/`, with its path.
Map<String, String> librarySources() {
  final root = Directory('${Directory.current.path}/lib');
  return {
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart'))
        file.path.split('/lib/').last: file.readAsStringSync(),
  };
}

/// The same sources with comments removed.
///
/// The purity properties are about what the package contains **as code**. A doc
/// comment explaining why no CLDR data ships here, or naming `inbox.unread` as
/// an example, is the documentation working rather than a violation — and a
/// check that forbids explaining itself would be a check nobody keeps.
///
/// Line-based, so a `//` inside a string literal would be stripped too. Good
/// enough: nothing here embeds one, and the alternative is a Dart parser.
Map<String, String> codeOnly(Map<String, String> sources) {
  return sources.map((path, source) {
    final stripped = source
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .split('\n')
        .map((line) {
          final comment = line.indexOf('//');
          return comment == -1 ? line : line.substring(0, comment);
        })
        .join('\n');
    return MapEntry(path, stripped);
  });
}

void main() {
  final sources = librarySources();
  final code = codeOnly(sources);

  test('the package has source to check', () {
    expect(sources, isNotEmpty);
    expect(sources.keys, contains('localaze.dart'));
    expect(code['signature.dart'], isNot(contains('///')),
        reason: 'the comment stripper is doing something');
  });

  test('purity.no-mf2-parser', () {
    // A device never sees MF2 syntax. Catalogs arrive already parsed, which is
    // what makes this package possible without a Dart MF2 library — there is
    // no maintained one, and decision D7 turns on that.
    for (final entry in code.entries) {
      expect(entry.value, isNot(contains('.match \$')), reason: entry.key);
      expect(entry.value, isNot(contains('.input {')), reason: entry.key);
      expect(entry.value, isNot(contains('{{')), reason: entry.key);
    }
  });

  test('purity.no-cldr-data', () {
    // Plural categories resolve through rules the generator compiled in, so no
    // CLDR tables ship here. The category names appear only as string keys in
    // catalogs, never as a rule table.
    for (final entry in code.entries) {
      expect(entry.value.toLowerCase(), isNot(contains('cldr')),
          reason: entry.key);
      // The generator reads the manifest's `pluralRules` field, which holds
      // conditions the server compiled. Reading that field is not shipping a
      // rule table, so it is the one place the name may appear.
      if (entry.key.startsWith('src/generator/')) continue;
      expect(entry.value, isNot(contains('pluralRules')), reason: entry.key);
    }
  });

  test('purity.no-translations-in-package', () {
    // The packages are generic: no key names, no translated text, no project
    // identifier. If a key from the fixture project appears here, something was
    // inlined that should have been generated.
    const leaks = [
      'inbox.unread',
      'auth.welcome',
      'auth.sign_out',
      'billing.due',
      'Postbox',
      'Выход',
      'mesaj',
    ];

    for (final entry in code.entries) {
      for (final leak in leaks) {
        expect(entry.value, isNot(contains(leak)),
            reason: '${entry.key} contains "$leak"');
      }
    }
  });

  test('purity.core-has-no-platform-io', () {
    // dart:io lives in lib/src/platform/ and nowhere else. This is what makes
    // Flutter Web work and what makes every failure path testable.
    final offenders = <String>[];

    for (final entry in sources.entries) {
      if (!entry.value.contains("import 'dart:io'")) continue;
      if (entry.key.startsWith('src/platform/')) continue;
      offenders.add(entry.key);
    }

    expect(offenders, isEmpty,
        reason: 'dart:io outside lib/src/platform/ breaks a web build');
  });

  test('the public entry point does not reach dart:io', () {
    // Transitively, not just directly: io.dart is a separate entry point and
    // localaze.dart must not export anything that pulls it in.
    final root = sources['localaze.dart']!;

    expect(root, isNot(contains('platform/')));
    expect(root, isNot(contains("import 'dart:io'")));

    for (final line in root.split('\n')) {
      if (!line.startsWith('export ')) continue;
      final path = RegExp(r"'([^']+)'").firstMatch(line)?.group(1);
      if (path == null) continue;
      expect(sources[path], isNot(contains("import 'dart:io'")),
          reason: 'localaze.dart exports $path, which imports dart:io');
    }
  });

  test('the package has no runtime dependencies', () {
    final pubspec = File('${Directory.current.path}/pubspec.yaml')
        .readAsStringSync()
        .split('dev_dependencies:')
        .first;

    // Every package here is one a consuming app must also carry and keep in
    // step. The only lines under `dependencies:` should be the key itself.
    final declared = pubspec
        .split('dependencies:')
        .last
        .split('\n')
        .where((line) => line.trimLeft().length != line.length)
        .where((line) => line.trim().isNotEmpty)
        .toList();

    expect(declared, isEmpty, reason: 'unexpected runtime dependency');
  });
}
