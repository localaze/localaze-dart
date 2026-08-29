/// Flutter binding for the Localaze runtime.
///
/// The core (`package:localaze`) is pure Dart and knows nothing about Flutter.
/// This package adds the two things a Flutter app wants: translations reachable
/// from a `BuildContext`, and a tree that rebuilds when the locale changes or
/// an over-the-air catalog is applied.
///
/// It depends on the core, never the reverse. That direction is what keeps a
/// CLI, a server, or the conformance suite free of a UI framework.
library;

export 'src/controller.dart' show LocalazeController, LocalazeFactory;
export 'src/delegate.dart' show LocalazeDelegate, LocalazeScope;

// Re-exported so an app configuring the SDK needs one import, not two.
//
// `LocalazeResponse` and `LocalazeNoStorage` are here because an app that
// supplies its own transport or storage — which a Flutter Web app must, since
// `dart:io` is unavailable there — cannot write one without them.
export 'package:localaze/localaze.dart'
    show
        LocalazeConfig,
        LocalazeFetchOutcome,
        LocalazeFetchStatus,
        LocalazeNoStorage,
        LocalazeResponse,
        LocalazeRuntime,
        LocalazeSignature,
        LocalazeStorage,
        LocalazeTransport,
        LocalazeUpdatePolicy;
