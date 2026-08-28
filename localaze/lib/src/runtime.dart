/// What generated code sits on.
///
/// A generated `Localaze` class holds one of these and calls [render] from each
/// typed accessor. The type safety lives in the generated signatures; this
/// supplies the content and the update machinery behind them.
library;

import 'catalog.dart';
import 'config.dart';
import 'diagnostics.dart';
import 'renderer.dart';
import 'signature.dart';
import 'storage.dart';
import 'store.dart';
import 'updater.dart';

/// Resolves a numeric value to a CLDR plural category for one locale.
///
/// Generated at build time from the project's locales, so the device resolves
/// categories without shipping CLDR data and without an MF2 parser. Returning
/// null means "no category", and the catch-all is used.
typedef LocalazePluralResolver = String? Function(num value);

class LocalazeRuntime {
  LocalazeRuntime({
    required this.locale,
    required this.config,
    required this.signature,
    required String compiledIn,
    LocalazePluralResolver? pluralResolver,
  })  : _diagnostics = Diagnostics(config.onDiagnostic),
        _pluralResolver = pluralResolver,
        _storage = config.storage ?? const LocalazeNoStorage() {
    final parsed = LocalazeCatalog.parse(compiledIn);
    _store = LocalazeStore(
      language: locale,
      // A compiled-in copy that will not parse is a generator bug, not a
      // runtime condition. Failing soft here keeps the no-throw rule intact and
      // leaves the app rendering key names, which is loud enough to notice.
      compiledIn: parsed ?? LocalazeCatalog.empty,
      signature: signature,
      diagnostics: _diagnostics,
    );
    if (parsed == null) {
      _diagnostics.report('The compiled-in $locale catalog could not be read');
    }
    _updater = LocalazeUpdater(
      config: config,
      signature: signature,
      diagnostics: _diagnostics,
      transport: config.transport,
      storage: _storage,
    );
  }

  final String locale;
  final LocalazeConfig config;
  final LocalazeSignature signature;
  final LocalazePluralResolver? _pluralResolver;
  final Diagnostics _diagnostics;
  final LocalazeStorage _storage;

  late final LocalazeStore _store;
  late final LocalazeUpdater _updater;

  LocalazeFetchStatus _lastFetch = LocalazeFetchStatus.idle;

  /// Held back until next launch when [LocalazeConfig.applyImmediately] is off.
  LocalazeCatalog? _pending;

  /// What happened on the last fetch. Readable so an app can report it rather
  /// than guess, which matters when nothing throws.
  LocalazeFetchStatus get lastFetch => _lastFetch;

  /// The version currently rendering.
  String get version => _store.version;

  /// Reads the bundled asset and any cached catalog.
  ///
  /// Optional — everything renders from the compiled-in copy without it — but
  /// an app that skips it gets no cached updates.
  Future<void> load() => _store.load(_storage);

  /// Fetches, checks and applies a newer catalog if the policy allows one.
  ///
  /// Never throws, and never blocks a screen: the app renders from what it has
  /// throughout. Returns the status, which is also stored on [lastFetch].
  Future<LocalazeFetchStatus> update({String? pinnedVersion}) async {
    final (catalog, status) = await _updater.fetchIfAccepted(
      locale,
      _store.version,
      pinnedVersion: pinnedVersion,
    );
    _lastFetch = status;

    if (catalog == null) return status;

    if (config.applyImmediately) {
      _store.apply(catalog);
    } else {
      // Text changing under a user mid-session is worse than text being one
      // launch out of date. It is cached either way, so next launch has it.
      _pending = catalog;
    }
    return status;
  }

  /// Applies a catalog held back by [LocalazeConfig.applyImmediately].
  ///
  /// An app with a natural seam — a navigation event, a background return —
  /// can call this rather than waiting for a relaunch.
  bool applyPending() {
    final pending = _pending;
    if (pending == null) return false;
    _store.apply(pending);
    _pending = null;
    return true;
  }

  /// Renders [key]. Called by generated accessors, which supply typed
  /// arguments; the loose map here is an internal boundary, not public API.
  ///
  /// Returns the key itself when it is not found anywhere. That is a generator
  /// bug rather than a runtime condition — generation fails on a missing
  /// translation — so it is reported rather than silently rendered as blank.
  String render(
    String key, {
    Map<String, Object?> args = const <String, Object?>{},
    num? selector,
  }) {
    final message = _store.lookup(key);
    if (message == null) {
      _diagnostics.report('No message for "$key" in $locale');
      return key;
    }

    String? category;
    if (message.selects && selector != null) {
      category = _pluralResolver?.call(selector);
    }

    final parts = message.partsFor(category);
    if (parts == null) {
      _diagnostics.report('"$key" has no variants in $locale');
      return key;
    }

    return localazeRender(parts, args,
        dateFormatter: config.dateFormatter);
  }
}
