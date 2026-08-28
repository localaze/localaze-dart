/// The `dart:io` defaults: HTTP over sockets, catalogs on disk.
///
/// Kept out of `package:localaze/localaze.dart` on purpose. Anything reachable
/// from the main entry point that imports `dart:io` breaks a Flutter Web build,
/// so a web app imports only the core and supplies its own transport and
/// storage. It is also why the conformance tests never touch a socket.
library;

export 'src/platform/io_storage.dart' show LocalazeFileStorage;
export 'src/platform/io_transport.dart' show LocalazeIoTransport;
