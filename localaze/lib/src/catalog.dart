/// The resolved message shape, and parsing it.
///
/// Catalogs arrive already parsed by the server, as variants and typed
/// parameter references. Nothing here parses MessageFormat 2, which is what
/// makes this package possible without a Dart MF2 library — there is no
/// maintained one, and decision D7 turns on that.
///
/// See `../../contract/runtime-contract.md` section 2.
library;

import 'dart:convert';

/// The three types a parameter can have. Deliberately small; the generators map
/// these onto native types and the set is not widened per platform.
enum LocalazeParamType {
  string,
  number,
  datetime;

  /// Wire values are upper case. An unknown type reads as a string rather than
  /// failing, so a newer server cannot break an older SDK.
  static LocalazeParamType parse(Object? wire) => switch (wire) {
        'NUMBER' => LocalazeParamType.number,
        'DATETIME' => LocalazeParamType.datetime,
        _ => LocalazeParamType.string,
      };
}

/// A parameter, with the type its MF2 function annotation implied.
class LocalazeParam {
  const LocalazeParam(this.name, this.type);

  final String name;
  final LocalazeParamType type;

  @override
  bool operator ==(Object other) =>
      other is LocalazeParam && other.name == name && other.type == type;

  @override
  int get hashCode => Object.hash(name, type);

  @override
  String toString() => '$name:${type.name}';
}

/// One piece of a message: literal text, or a reference to a parameter.
///
/// Exactly one of [text] and [variable] is set. The server omits null fields,
/// so a part with neither is malformed and is skipped at render time rather
/// than failing the whole message.
class LocalazePart {
  const LocalazePart.text(String this.text)
      : variable = null,
        type = null;

  const LocalazePart.variable(String this.variable, this.type) : text = null;

  final String? text;
  final String? variable;
  final LocalazeParamType? type;

  bool get isMalformed => text == null && variable == null;
}

/// A message resolved into parts and variants.
class LocalazeMessage {
  const LocalazeMessage({
    required this.selectors,
    required this.params,
    required this.variants,
  });

  /// Parameters the message selects on. Empty for a simple message.
  final List<String> selectors;

  /// Every parameter, with its type.
  final List<LocalazeParam> params;

  /// Variant category to its ordered parts. A simple message has only `*`.
  final Map<String, List<LocalazePart>> variants;

  bool get selects => selectors.isNotEmpty;

  /// The parts for [category], falling back to the catch-all.
  ///
  /// `LZ-07` guarantees `*` is present on every message, which is what makes
  /// this fallback safe rather than optimistic.
  List<LocalazePart>? partsFor(String? category) {
    if (category != null) {
      final exact = variants[category];
      if (exact != null) return exact;
    }
    return variants['*'];
  }

  static LocalazeMessage? _parse(Object? raw) {
    if (raw is! Map) return null;

    final variants = <String, List<LocalazePart>>{};
    final rawVariants = raw['variants'];
    if (rawVariants is! Map) return null;

    for (final entry in rawVariants.entries) {
      final parts = <LocalazePart>[];
      final rawParts = entry.value;
      if (rawParts is! List) continue;
      for (final rawPart in rawParts) {
        if (rawPart is! Map) continue;
        final text = rawPart['text'];
        final variable = rawPart['var'];
        if (text is String) {
          parts.add(LocalazePart.text(text));
        } else if (variable is String) {
          parts.add(
              LocalazePart.variable(variable, LocalazeParamType.parse(rawPart['type'])));
        }
        // A part with neither is dropped here rather than carried and skipped
        // later; the effect a caller sees is the same and the model stays clean.
      }
      variants['${entry.key}'] = parts;
    }
    if (variants.isEmpty) return null;

    return LocalazeMessage(
      selectors: _stringList(raw['selectors']),
      params: _params(raw['params']),
      variants: variants,
    );
  }

  static List<String> _stringList(Object? raw) =>
      raw is List ? raw.whereType<String>().toList(growable: false) : const [];

  static List<LocalazeParam> _params(Object? raw) {
    if (raw is! List) return const [];
    final params = <LocalazeParam>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = entry['name'];
      if (name is String) {
        params.add(LocalazeParam(name, LocalazeParamType.parse(entry['type'])));
      }
    }
    return params;
  }
}

/// One language's messages, and the release they came from.
///
/// A catalog file and a read-API response body have the same shape, so a
/// bundled asset and a fetched payload go through this one parser. Inventing a
/// second envelope for bundled files would mean two code paths where one is
/// tested and the other is not.
class LocalazeCatalog {
  const LocalazeCatalog(this.version, this.messages);

  final String version;
  final Map<String, LocalazeMessage> messages;

  static const LocalazeCatalog empty =
      LocalazeCatalog('0.0.0', <String, LocalazeMessage>{});

  bool get isEmpty => messages.isEmpty;

  /// Parses a catalog, returning null rather than throwing.
  ///
  /// Malformed JSON, a missing `messages` object, and a body that is not an
  /// object at all all return null. The caller keeps whatever it already had.
  static LocalazeCatalog? parse(String body, {String? fallbackVersion}) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final rawMessages = decoded['messages'];
    if (rawMessages is! Map) return null;

    final messages = <String, LocalazeMessage>{};
    for (final entry in rawMessages.entries) {
      final message = LocalazeMessage._parse(entry.value);
      if (message != null) messages['${entry.key}'] = message;
    }

    final version = decoded['version'];
    return LocalazeCatalog(
      version is String ? version : (fallbackVersion ?? '0.0.0'),
      messages,
    );
  }
}
