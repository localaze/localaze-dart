/// Everything the generator decides before it writes a line of Dart.
///
/// The checks of `contract/generator-contract.md` §4 all live here, so the
/// emitter receives a plan that is already known to compile. Nothing in this
/// file touches the network or the filesystem: the command in `bin/` reads the
/// inputs and writes the outputs, and the tests drive this directly.
library;

import 'dart:convert';

/// One parameter of a key, as the manifest declares it.
final class PlannedParam {
  const PlannedParam(this.name, this.identifier, this.type);

  /// The name the catalog uses. Passed to the runtime unchanged.
  final String name;

  /// The lower-camel identifier the accessor declares, before escaping.
  final String identifier;

  /// `STRING`, `NUMBER` or `DATETIME`.
  final String type;
}

/// One key, ready to become an accessor.
final class PlannedKey {
  const PlannedKey({
    required this.key,
    required this.accessor,
    required this.params,
    required this.selector,
    required this.preview,
  });

  final String key;

  /// The lower-camel accessor name, before escaping.
  final String accessor;

  final List<PlannedParam> params;

  /// The parameter the message selects on, or null for a simple message.
  final String? selector;

  /// The source-language text, for the accessor's documentation comment.
  final String preview;
}

/// One language's plural resolver.
final class PlannedPlural {
  const PlannedPlural(this.language, this.categories);

  final String language;

  /// Category to condition, in the manifest's order.
  final List<(String, String)> categories;

  /// Whether any condition mentions [operand].
  bool uses(String operand) =>
      categories.any((entry) => RegExp('\\b$operand\\b').hasMatch(entry.$2));
}

/// A plan the emitter can turn into source without any further checks.
final class GenerationPlan {
  const GenerationPlan({
    required this.environment,
    required this.version,
    required this.contentHash,
    required this.sourceLanguage,
    required this.languages,
    required this.keys,
    required this.plurals,
    required this.catalogs,
  });

  final String environment;
  final String version;
  final String contentHash;
  final String sourceLanguage;

  /// The manifest's languages, in its order.
  final List<String> languages;

  final List<PlannedKey> keys;
  final List<PlannedPlural> plurals;

  /// Language to the catalog exactly as it was read, in [languages] order.
  final Map<String, String> catalogs;
}

/// What planning produced: a plan, or every reason there is none.
final class PlanResult {
  const PlanResult(this.plan, this.problems, this.warnings);

  final GenerationPlan? plan;

  /// Each one fails generation.
  final List<String> problems;

  /// Reported, not fatal. Only `--allow-gaps` produces these.
  final List<String> warnings;
}

/// Members of the generated type, plus members a base type already has on at
/// least one platform. Reserved on every platform alike, so a key set that
/// generates for Dart also generates for Swift and Kotlin.
const Set<String> reservedAccessors = <String>{
  'runtime',
  'forLocale',
  'supportedLocales',
  'sourceLocale',
  'generatedFrom',
  'contentHash',
  'hashCode',
  'toString',
  'equals',
  'runtimeType',
  'noSuchMethod',
};

const Set<String> _types = <String>{'STRING', 'NUMBER', 'DATETIME'};
const Set<String> _operands = <String>{'n', 'i', 'v'};
final RegExp _identifier = RegExp(r'^[A-Za-z][A-Za-z0-9]*$');
final RegExp _ruleCharacters = RegExp(r'^[niv0-9\s()%=!<>&|]*$');
final RegExp _category = RegExp(r'^[a-z]+$');
const int _previewLength = 80;

/// `auth.sign_out` becomes `authSignOut`. The same rule names parameters.
String lowerCamel(String raw) {
  final segments =
      raw.split(RegExp(r'[._-]')).where((segment) => segment.isNotEmpty);
  final out = StringBuffer();
  for (final segment in segments) {
    final head = segment.substring(0, 1);
    out.write(out.isEmpty ? head.toLowerCase() : head.toUpperCase());
    out.write(segment.substring(1));
  }
  return out.toString();
}

/// Plans generation from a manifest and one catalog per language, each the raw
/// text the server returned or the file a build saved.
PlanResult plan({
  required String manifest,
  required Map<String, String> catalogs,
  bool allowGaps = false,
}) {
  final problems = <String>[];
  final warnings = <String>[];

  final parsed = _decode(manifest, 'The manifest', problems);
  if (parsed == null) return PlanResult(null, problems, warnings);

  final version = _string(parsed, 'version', problems);
  final sourceLanguage = _string(parsed, 'sourceLanguage', problems);
  final languages = _strings(parsed['languages'], 'languages', problems);
  final keys = _manifestKeys(parsed['keys'], problems);
  final rules = _rules(parsed['pluralRules'], problems);
  if (problems.isNotEmpty) return PlanResult(null, problems, warnings);

  final messages = <String, Map<String, Object?>>{};
  for (final language in languages) {
    final raw = catalogs[language];
    if (raw == null) {
      problems.add('No catalog for language "$language".');
      continue;
    }
    final catalog = _decode(raw, 'The "$language" catalog', problems);
    if (catalog == null) continue;
    if (catalog['version'] != version) {
      problems.add('The "$language" catalog is version '
          '${catalog['version']}, but the manifest is $version.');
    }
    final body = catalog['messages'];
    if (body is! Map<String, Object?>) {
      problems.add('The "$language" catalog has no "messages".');
      continue;
    }
    messages[language] = body;
  }

  for (final key in keys) {
    for (final language in messages.keys) {
      if (!messages[language]!.containsKey(key.key)) {
        final gap = '${key.key} is missing in $language.';
        (allowGaps ? warnings : problems).add(gap);
      }
    }
  }

  final planned = _planKeys(keys, sourceLanguage, languages, messages, problems);
  final plurals = _planPlurals(languages, rules, problems);

  if (problems.isNotEmpty) return PlanResult(null, problems, warnings);

  return PlanResult(
    GenerationPlan(
      environment: parsed['environment'] is String
          ? parsed['environment']! as String
          : 'unknown',
      version: version,
      contentHash: parsed['contentHash'] is String
          ? parsed['contentHash']! as String
          : '',
      sourceLanguage: sourceLanguage,
      languages: languages,
      keys: planned,
      plurals: plurals,
      catalogs: <String, String>{
        for (final language in languages) language: catalogs[language]!,
      },
    ),
    problems,
    warnings,
  );
}

final class _ManifestKey {
  const _ManifestKey(this.key, this.params, this.selects);

  final String key;
  final List<(String, String)> params;
  final bool selects;
}

List<PlannedKey> _planKeys(
  List<_ManifestKey> keys,
  String sourceLanguage,
  List<String> languages,
  Map<String, Map<String, Object?>> messages,
  List<String> problems,
) {
  final planned = <PlannedKey>[];
  final owners = <String, String>{};

  for (final key in keys) {
    final accessor = lowerCamel(key.key);
    if (!_identifier.hasMatch(accessor)) {
      problems.add('Key "${key.key}" gives no valid accessor name '
          '("$accessor"). Use ASCII letters and digits, starting with a letter.');
    } else if (reservedAccessors.contains(accessor)) {
      problems.add('Key "${key.key}" would generate "$accessor", '
          'which is reserved.');
    } else if (owners.containsKey(accessor)) {
      problems.add('Keys "${owners[accessor]}" and "${key.key}" both '
          'generate the accessor "$accessor".');
    } else {
      owners[accessor] = key.key;
    }

    final params = <PlannedParam>[];
    final seen = <String, String>{};
    for (final (name, type) in key.params) {
      final identifier = lowerCamel(name);
      if (!_identifier.hasMatch(identifier)) {
        problems.add('Parameter "$name" of "${key.key}" gives no valid '
            'identifier ("$identifier").');
      } else if (seen.containsKey(identifier)) {
        problems.add('Parameters "${seen[identifier]}" and "$name" of '
            '"${key.key}" both generate "$identifier".');
      } else {
        seen[identifier] = name;
      }
      params.add(PlannedParam(name, identifier, type));
    }

    final reference =
        _reference(key.key, sourceLanguage, languages, messages);
    final selector = key.selects
        ? _selector(key, reference, problems)
        : null;

    planned.add(PlannedKey(
      key: key.key,
      accessor: accessor,
      params: params,
      selector: selector,
      preview: _preview(reference),
    ));
  }
  return planned;
}

/// The source language's message, or the first language that has the key.
Map<String, Object?>? _reference(
  String key,
  String sourceLanguage,
  List<String> languages,
  Map<String, Map<String, Object?>> messages,
) {
  for (final language in <String>[sourceLanguage, ...languages]) {
    final message = messages[language]?[key];
    if (message is Map<String, Object?>) return message;
  }
  return null;
}

String? _selector(
  _ManifestKey key,
  Map<String, Object?>? reference,
  List<String> problems,
) {
  final selectors = reference?['selectors'];
  if (selectors is! List || selectors.isEmpty || selectors.first is! String) {
    problems.add('"${key.key}" selects, but no catalog names its selector.');
    return null;
  }
  final name = selectors.first as String;
  final declared = key.params.where((param) => param.$1 == name);
  if (declared.isEmpty) {
    problems.add('"${key.key}" selects on \$$name, which the manifest '
        'does not declare.');
    return null;
  }
  if (declared.first.$2 != 'NUMBER') {
    problems.add('"${key.key}" selects on \$$name, a ${declared.first.$2}. '
        'Only NUMBER selection runs on device.');
    return null;
  }
  return name;
}

/// The `*` variant as text, variables as `{$name}`, on one line.
String _preview(Map<String, Object?>? message) {
  final variants = message?['variants'];
  final parts = variants is Map ? variants['*'] : null;
  if (parts is! List) return '';

  final out = StringBuffer();
  for (final part in parts) {
    if (part is! Map) continue;
    if (part['text'] is String) {
      out.write(part['text']);
    } else if (part['var'] is String) {
      out.write('{\$${part['var']}}');
    }
  }
  final line = out.toString().replaceAll(RegExp(r'[\r\n\t]+'), ' ');
  if (line.length <= _previewLength) return line;

  // Never cut a surrogate pair in half: a lone surrogate is not text.
  var end = _previewLength;
  final last = line.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
  return '${line.substring(0, end)}…';
}

List<PlannedPlural> _planPlurals(
  List<String> languages,
  Map<String, List<(String, String)>> rules,
  List<String> problems,
) {
  final plurals = <PlannedPlural>[];
  for (final language in languages) {
    final categories = rules[language] ?? const <(String, String)>[];
    for (final (category, condition) in categories) {
      if (!_category.hasMatch(category)) {
        problems.add('The "$language" plural rules name an unrecognised '
            'category "$category".');
      }
      final operands = RegExp(r'[A-Za-z_]+')
          .allMatches(condition)
          .map((match) => match.group(0)!)
          .where((token) => !_operands.contains(token))
          .toSet();
      if (operands.isNotEmpty) {
        problems.add('The "$language" rule for "$category" uses '
            '${operands.join(', ')}. Only n, i and v are supported.');
      } else if (!_ruleCharacters.hasMatch(condition)) {
        problems.add('The "$language" rule for "$category" is not a '
            'recognised condition: $condition');
      }
    }
    plurals.add(PlannedPlural(language, categories));
  }
  return plurals;
}

// ── Parsing ──────────────────────────────────────────────────────────────────

Map<String, Object?>? _decode(String raw, String what, List<String> problems) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, Object?>) return decoded;
    problems.add('$what is not a JSON object.');
  } on FormatException catch (error) {
    problems.add('$what is not valid JSON: ${error.message}');
  }
  return null;
}

String _string(Map<String, Object?> json, String field, List<String> problems) {
  final value = json[field];
  if (value is String && value.isNotEmpty) return value;
  problems.add('The manifest has no "$field".');
  return '';
}

List<String> _strings(Object? value, String field, List<String> problems) {
  if (value is List && value.isNotEmpty && value.every((e) => e is String)) {
    return value.cast<String>();
  }
  problems.add('The manifest has no "$field".');
  return const <String>[];
}

List<_ManifestKey> _manifestKeys(Object? value, List<String> problems) {
  if (value is! List) {
    problems.add('The manifest has no "keys".');
    return const <_ManifestKey>[];
  }
  final keys = <_ManifestKey>[];
  for (final entry in value) {
    if (entry is! Map || entry['key'] is! String || entry['params'] is! List) {
      problems.add('The manifest has a key entry it cannot read: $entry');
      continue;
    }
    final params = <(String, String)>[];
    for (final param in entry['params'] as List) {
      if (param is Map &&
          param['name'] is String &&
          _types.contains(param['type'])) {
        params.add((param['name'] as String, param['type'] as String));
      } else {
        problems.add('"${entry['key']}" declares a parameter it cannot '
            'read: $param');
      }
    }
    keys.add(_ManifestKey(
        entry['key'] as String, params, entry['selects'] == true));
  }
  return keys;
}

Map<String, List<(String, String)>> _rules(
    Object? value, List<String> problems) {
  if (value == null) return const <String, List<(String, String)>>{};
  if (value is! Map) {
    problems.add('The manifest\'s "pluralRules" is not an object.');
    return const <String, List<(String, String)>>{};
  }
  final rules = <String, List<(String, String)>>{};
  value.forEach((language, categories) {
    if (language is! String || categories is! Map) {
      problems.add('The manifest has plural rules it cannot read for '
          '"$language".');
      return;
    }
    // Name order, per generator-contract.md §7, so every platform agrees
    // whether or not its JSON reader keeps an object's order.
    rules[language] = <(String, String)>[
      for (final entry in categories.entries)
        if (entry.key is String && entry.value is String)
          (entry.key as String, entry.value as String),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
  });
  return rules;
}
