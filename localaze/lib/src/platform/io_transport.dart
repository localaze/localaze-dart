/// The default transport. The only network code in the package.
///
/// This file and `io_storage.dart` are the only ones permitted to import
/// `dart:io`, and neither is reachable from `package:localaze/localaze.dart`.
library;

import 'dart:convert';
import 'dart:io';

import '../transport.dart';

class LocalazeIoTransport implements LocalazeTransport {
  LocalazeIoTransport({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;

  /// Returns a failed response rather than throwing, whatever goes wrong.
  ///
  /// A caller that has to wrap every call in a try/catch has an interface that
  /// lied to it, and this one promises not to throw.
  @override
  Future<LocalazeResponse> get(String url, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      headers.forEach(request.headers.set);

      final response = await request.close().timeout(timeout);
      final etag = response.headers.value(HttpHeaders.etagHeader);

      // 304 carries no body, and reading one would hang until the timeout.
      if (response.statusCode == HttpStatus.notModified) {
        await response.drain<void>();
        return LocalazeResponse(status: response.statusCode, etag: etag);
      }

      // utf8 explicitly, not the system encoding: catalogs carry Cyrillic and
      // Azerbaijani, and a locale-dependent decoder would mangle both.
      final body = await response.transform(utf8.decoder).join();
      return LocalazeResponse(
        status: response.statusCode,
        body: body,
        etag: etag,
      );
    } catch (error) {
      return LocalazeResponse.failed(error);
    } finally {
      client.close(force: true);
    }
  }
}
