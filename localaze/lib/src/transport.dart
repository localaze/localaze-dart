/// The network seam.
///
/// An interface rather than a direct `dart:io` call, for two reasons that are
/// both about this package being usable and testable: `dart:io` is unavailable
/// on Flutter Web, and every failure row in the contract is reachable with a
/// fake and unreachable without one.
///
/// See `contract/runtime-contract.md` section 10.
library;

/// What came back. Never an exception — an implementation that cannot reach the
/// network returns [LocalazeResponse.failed] instead.
class LocalazeResponse {
  const LocalazeResponse({
    required this.status,
    this.body,
    this.etag,
    this.error,
  });

  /// A request that never completed. Status 0 is not a real HTTP status, which
  /// is the point: it cannot collide with one the server might send.
  const LocalazeResponse.failed(Object this.error)
      : status = 0,
        body = null,
        etag = null;

  final int status;
  final String? body;
  final String? etag;
  final Object? error;

  bool get isOk => status == 200;

  /// The server had nothing newer. A success, not a failure — this is the cheap
  /// path the version-scoped ETag exists to serve.
  bool get isNotModified => status == 304;
}

/// One GET, with headers. Implementations must not throw.
abstract interface class LocalazeTransport {
  Future<LocalazeResponse> get(String url, Map<String, String> headers);
}
