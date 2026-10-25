/// Reporting swallowed failures.
///
/// Nothing in this package throws, which is a deliberate choice and a dangerous
/// one: a wrong API key and a quiet network look identical from the outside, so
/// an integration that never worked can go unnoticed for a month. The callback
/// is not optional polish, it is how anyone finds out.
///
/// See `contract/runtime-contract.md` section 8.
library;

/// Called for every failure the package declines to throw.
typedef LocalazeDiagnostic = void Function(String message, Object? error);

/// Wraps the app's callback so a broken one cannot take the app with it.
class Diagnostics {
  const Diagnostics(this._callback);

  final LocalazeDiagnostic? _callback;

  void report(String message, [Object? error]) {
    final callback = _callback;
    if (callback == null) return;
    try {
      callback(message, error);
    } catch (_) {
      // An app whose diagnostic handler throws still gets its translations.
      // Reporting this would mean calling the thing that just failed.
    }
  }
}

/// What happened on the last fetch, so an app can report it rather than guess.
enum LocalazeFetchOutcome {
  /// No fetch has been attempted.
  none,

  /// A newer catalog was downloaded, checked and applied.
  applied,

  /// The server had nothing newer, or returned 304.
  upToDate,

  /// The update policy declined it.
  refusedByPolicy,

  /// The signature check declined it. On a minor or patch release this is a
  /// platform bug — `LZ-62` guarantees those are signature-compatible.
  refusedBySignature,

  /// The network, the server, or the payload failed.
  failed,
}

/// The outcome of the last fetch, and why.
class LocalazeFetchStatus {
  const LocalazeFetchStatus(this.outcome, {this.detail, this.version});

  static const LocalazeFetchStatus idle =
      LocalazeFetchStatus(LocalazeFetchOutcome.none);

  final LocalazeFetchOutcome outcome;

  /// Human-readable, and the same text passed to the diagnostic callback.
  final String? detail;

  /// The version involved, when there was one.
  final String? version;

  bool get isApplied => outcome == LocalazeFetchOutcome.applied;

  @override
  String toString() =>
      'LocalazeFetchStatus(${outcome.name}${detail == null ? '' : ': $detail'})';
}
