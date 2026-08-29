/// The transport and storage this app supplies to the SDK.
///
/// Worth reading even though it is short: it is the whole reason the SDK takes
/// interfaces rather than calling the network itself.
///
/// `package:localaze/io.dart` ships `dart:io` implementations that are right
/// for a device build. This app also runs on web, where `dart:io` does not
/// exist, so it supplies its own — and that is the supported path, not a
/// workaround.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:localaze/localaze.dart';

/// A transport over `package:http`, which works on every Flutter target.
class HttpTransport implements LocalazeTransport {
  HttpTransport({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;
  final http.Client _client = http.Client();

  /// Returns a failed response rather than throwing, whatever goes wrong.
  ///
  /// The interface promises not to throw, and the updater catches it anyway —
  /// but a transport that keeps its own promise makes the diagnostic say what
  /// actually happened rather than "threw".
  @override
  Future<LocalazeResponse> get(String url, Map<String, String> headers) async {
    try {
      final response =
          await _client.get(Uri.parse(url), headers: headers).timeout(timeout);

      return LocalazeResponse(
        status: response.statusCode,
        // utf8 explicitly: catalogs carry Cyrillic and Azerbaijani, and
        // response.body guesses the charset from the header.
        body: response.statusCode == 304
            ? null
            : utf8.decode(response.bodyBytes),
        etag: response.headers['etag'],
      );
    } catch (error) {
      return LocalazeResponse.failed(error);
    }
  }
}

/// Reads bundled catalogs from Flutter assets.
///
/// Caching is left unimplemented on purpose, and the app says so on screen: it
/// would need `path_provider`, and the SDK deliberately does not depend on it.
/// An applied update therefore lasts for the session, which is the documented
/// default when no cache is configured — not a failure.
class AssetStorage implements LocalazeStorage {
  const AssetStorage({this.assetPath = 'assets/localaze'});

  final String assetPath;

  @override
  Future<String?> readAsset(String language) async {
    try {
      return await rootBundle.loadString('$assetPath/$language.json');
    } catch (_) {
      // A missing asset is expected rather than exceptional — the compiled-in
      // copy sits behind it.
      return null;
    }
  }

  @override
  Future<String?> readCache(String language) async => null;

  @override
  Future<bool> writeCache(String language, String body) async => false;
}
