/// Where content comes from, and in what order.
///
/// See `contract/runtime-contract.md` section 7.
library;

import 'catalog.dart';
import 'diagnostics.dart';
import 'signature.dart';
import 'storage.dart';

/// Holds the four levels of content for one language and answers lookups from
/// the highest that has the key.
///
/// **Per key, not per catalog.** A partial or stale catalog degrades key by key
/// rather than wholly, so one missing key does not cost an app every string it
/// has. That is the only reason the levels are kept separate rather than merged
/// once at load.
class LocalazeStore {
  LocalazeStore({
    required this.language,
    required LocalazeCatalog compiledIn,
    required this.signature,
    required Diagnostics diagnostics,
  })  : _compiledIn = compiledIn,
        _diagnostics = diagnostics;

  final String language;
  final LocalazeSignature signature;
  final Diagnostics _diagnostics;

  /// Level 4, the floor. Shipped inside the generated source.
  ///
  /// It is duplication and it earns its place: without it the first launch of a
  /// fresh install with no network has no text at all, and a mistyped asset
  /// path fails as a blank screen rather than a stale one.
  final LocalazeCatalog _compiledIn;

  LocalazeCatalog? _bundled;
  LocalazeCatalog? _cached;
  LocalazeCatalog? _applied;

  /// The version currently rendering, so an app can report it.
  String get version =>
      (_applied ?? _cached ?? _bundled ?? _compiledIn).version;

  /// Reads the bundled asset and any cached catalog.
  ///
  /// Both are optional and neither failing is an error. The cached catalog is
  /// checked against the signature again here, because an app upgrade can leave
  /// yesterday's catalog next to code that now promises something else.
  Future<void> load(LocalazeStorage storage) async {
    final asset = await _read(() => storage.readAsset(language), 'bundled');
    if (asset != null) {
      final parsed = LocalazeCatalog.parse(asset);
      if (parsed == null) {
        _diagnostics.report('The bundled $language catalog could not be read');
      } else {
        _bundled = parsed;
      }
    }

    final cached = await _read(() => storage.readCache(language), 'cached');
    if (cached == null) return;

    final parsed = LocalazeCatalog.parse(cached);
    if (parsed == null) {
      _diagnostics.report('Ignoring an unreadable cached $language catalog');
      return;
    }

    final problems = signature.incompatibilities(parsed);
    if (problems.isNotEmpty) {
      _diagnostics.report('Dropping the cached $language catalog '
          '${parsed.version}: ${problems.join(', ')}');
      return;
    }
    _cached = parsed;
  }

  /// A storage implementation is told not to throw. One supplied by an app
  /// might anyway, and [load] is the first thing an app calls — letting it
  /// propagate would break the no-throw rule at the worst moment.
  Future<String?> _read(Future<String?> Function() read, String what) async {
    try {
      return await read();
    } catch (error) {
      _diagnostics.report('Could not read the $what $language catalog', error);
      return null;
    }
  }

  /// Takes a catalog that has already passed policy and signature.
  void apply(LocalazeCatalog catalog) => _applied = catalog;

  /// The message for [key], from the highest level that has it.
  LocalazeMessage? lookup(String key) {
    return _applied?.messages[key] ??
        _cached?.messages[key] ??
        _bundled?.messages[key] ??
        _compiledIn.messages[key];
  }
}
