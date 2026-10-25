/// The persistence seam.
///
/// Two separate concerns behind one interface: reading the bundled asset that
/// shipped with the app, and reading or writing the cache that survives a
/// launch. They fail differently and are configured differently, so they are
/// separate methods rather than one keyed store.
///
/// See `contract/runtime-contract.md` sections 7 and 10.
library;

/// Implementations must not throw. Anything unreadable is null.
abstract interface class LocalazeStorage {
  /// The catalog that shipped with the app, for [language].
  ///
  /// Null when there is no asset, or it cannot be read. A missing asset is not
  /// an error: the compiled-in copy is behind it, which is what lets the asset
  /// path be configurable without a typo becoming a blank screen.
  Future<String?> readAsset(String language);

  /// A catalog written by an earlier run.
  Future<String?> readCache(String language);

  /// Persists [body]. Returns false when it could not be written.
  ///
  /// False is not a failure worth stopping for — the update still applies for
  /// this session. It is reported so an app can tell "working, not persisted"
  /// from "working".
  Future<bool> writeCache(String language, String body);
}

/// Storage that has nothing and keeps nothing.
///
/// The default when an app configures no cache directory, and what makes
/// session-only updates the documented behaviour rather than a special case in
/// the store.
class LocalazeNoStorage implements LocalazeStorage {
  const LocalazeNoStorage();

  @override
  Future<String?> readAsset(String language) async => null;

  @override
  Future<String?> readCache(String language) async => null;

  @override
  Future<bool> writeCache(String language, String body) async => false;
}
