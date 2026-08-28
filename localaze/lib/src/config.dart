/// Everything an app can change, all of it optional but the key.
///
/// See `../../contract/runtime-contract.md` section 9.
library;

import 'diagnostics.dart';
import 'renderer.dart';
import 'storage.dart';
import 'transport.dart';
import 'version.dart';

// Re-exported so an app configuring a policy does not need a second import.
export 'version.dart' show LocalazeUpdatePolicy;

class LocalazeConfig {
  const LocalazeConfig({
    required this.apiKey,
    this.baseUrl = 'https://localize.sharpy.dev',
    this.policy = LocalazeUpdatePolicy.minorAndPatch,
    this.timeout = const Duration(seconds: 10),
    this.applyImmediately = false,
    this.dateFormatter = localazeIsoUtc,
    this.onDiagnostic,
    this.transport,
    this.storage,
  });

  /// Issued in project settings. Carries the project and the environment, so
  /// neither is a parameter here and a staging build cannot read production.
  final String apiKey;

  final String baseUrl;

  final LocalazeUpdatePolicy policy;

  final Duration timeout;

  /// Whether an applied catalog takes effect now or on next launch.
  ///
  /// Off by default: text changing under a user mid-session is worse than text
  /// being one launch out of date.
  final bool applyImmediately;

  final LocalazeDateFormatter dateFormatter;

  /// The only way to hear about failures. See [Diagnostics].
  final LocalazeDiagnostic? onDiagnostic;

  /// Defaults to no network. Import `package:localaze/io.dart` for the
  /// `dart:io` implementation, or supply one — a web app must, since `dart:io`
  /// is unavailable there.
  final LocalazeTransport? transport;

  /// Defaults to [LocalazeNoStorage], so updates last for the session only.
  /// Import `package:localaze/io.dart` for file-backed storage.
  final LocalazeStorage? storage;

  LocalazeConfig copyWith({
    LocalazeTransport? transport,
    LocalazeStorage? storage,
    LocalazeUpdatePolicy? policy,
  }) {
    return LocalazeConfig(
      apiKey: apiKey,
      baseUrl: baseUrl,
      policy: policy ?? this.policy,
      timeout: timeout,
      applyImmediately: applyImmediately,
      dateFormatter: dateFormatter,
      onDiagnostic: onDiagnostic,
      transport: transport ?? this.transport,
      storage: storage ?? this.storage,
    );
  }
}
