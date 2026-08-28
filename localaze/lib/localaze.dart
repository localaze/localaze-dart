/// The Localaze runtime for Dart and Flutter.
///
/// Pure Dart and web-safe: nothing reachable from here imports `dart:io`. The
/// default file and network implementations live in `package:localaze/io.dart`,
/// which a Flutter Web app does not import and supplies its own instead.
///
/// Nothing in this library throws. Every failure leaves the app on the content
/// it already had and is reported through [LocalazeConfig.onDiagnostic].
library;

export 'src/catalog.dart'
    show
        LocalazeCatalog,
        LocalazeMessage,
        LocalazeParam,
        LocalazeParamType,
        LocalazePart;
export 'src/config.dart' show LocalazeConfig;
export 'src/diagnostics.dart'
    show LocalazeDiagnostic, LocalazeFetchOutcome, LocalazeFetchStatus;
export 'src/renderer.dart'
    show LocalazeDateFormatter, localazeIsoUtc, localazeRender;
export 'src/runtime.dart' show LocalazePluralResolver, LocalazeRuntime;
export 'src/signature.dart' show LocalazeSignature;
export 'src/storage.dart' show LocalazeNoStorage, LocalazeStorage;
export 'src/store.dart' show LocalazeStore;
export 'src/transport.dart' show LocalazeResponse, LocalazeTransport;
export 'src/updater.dart' show LocalazeUpdater;
export 'src/version.dart' show LocalazeUpdatePolicy, LocalazeVersion;
