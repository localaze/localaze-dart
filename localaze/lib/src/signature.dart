/// What the generated code promised its call sites, and checking a catalog
/// against it.
///
/// See `contract/runtime-contract.md` section 4.
library;

import 'catalog.dart';

/// Keys to the parameters each accessor takes.
///
/// Emitted into the generated source and never fetched, because it describes
/// the code that was compiled rather than the content that arrives.
class LocalazeSignature {
  const LocalazeSignature(this.keys);

  final Map<String, List<LocalazeParam>> keys;

  /// Builds a signature from the compact form generated code emits:
  /// `{'inbox.unread': [('count', 'NUMBER')]}`.
  factory LocalazeSignature.of(Map<String, List<(String, String)>> raw) {
    return LocalazeSignature({
      for (final entry in raw.entries)
        entry.key: [
          for (final (name, type) in entry.value)
            LocalazeParam(name, LocalazeParamType.parse(type)),
        ],
    });
  }

  /// Why [catalog] cannot be applied, empty when it can.
  ///
  /// Three rules, and each one is a decision rather than an oversight:
  ///
  /// - A **missing key** is incompatible. Generated code has an accessor for it
  ///   and nothing to render.
  /// - A parameter whose **name or type** differs is incompatible. Checking
  ///   names alone is the defect this replaces: `{$count}` gaining `:number`
  ///   leaves the key and the name intact while changing what every call site
  ///   passes, and it is the likelier edit in practice than a removal.
  /// - An **added key**, or an **extra parameter** on a key we do know, is
  ///   fine. The app has no accessor for either, and a newer platform release
  ///   is not a client failure. The signature is a floor, not an equality.
  List<String> incompatibilities(LocalazeCatalog catalog) {
    final problems = <String>[];

    for (final entry in keys.entries) {
      final message = catalog.messages[entry.key];
      if (message == null) {
        problems.add('${entry.key} is missing');
        continue;
      }

      final declared = <String, LocalazeParamType>{
        for (final param in message.params) param.name: param.type,
      };

      for (final expected in entry.value) {
        final actual = declared[expected.name];
        if (actual == null) {
          problems.add('${entry.key} no longer takes "${expected.name}"');
        } else if (actual != expected.type) {
          problems.add('${entry.key}.${expected.name} is now '
              '${actual.name}, generated as ${expected.type.name}');
        }
      }
    }
    return problems;
  }

  bool accepts(LocalazeCatalog catalog) => incompatibilities(catalog).isEmpty;
}
