/// Fakes for transport and storage.
///
/// These exist because every failure row in contract section 8 is reachable
/// with a fake and unreachable without one. A runtime testable only against a
/// live server is a runtime that is not tested.
library;

import 'dart:io';

import 'package:localaze/localaze.dart';

/// Records what it was asked for and returns what it was told to.
class FakeTransport implements LocalazeTransport {
  FakeTransport(this.responses);

  /// Path suffix to response. Matched by `endsWith`, so a caller writes
  /// `/version` rather than the whole URL.
  final Map<String, LocalazeResponse> responses;

  final List<String> urls = <String>[];
  final List<Map<String, String>> headers = <Map<String, String>>[];

  /// Set to throw from [get], to prove the updater catches a transport that
  /// breaks its own contract.
  Object? throwOnGet;

  Map<String, String> get lastHeaders => headers.last;

  bool sawHeader(String name) => headers.any((h) => h.containsKey(name));

  String? headerValue(String name) => headers
      .where((h) => h.containsKey(name))
      .map((h) => h[name])
      .firstOrNull;

  @override
  Future<LocalazeResponse> get(String url, Map<String, String> headers) async {
    urls.add(url);
    this.headers.add(Map<String, String>.from(headers));

    final failure = throwOnGet;
    if (failure != null) throw failure;

    for (final entry in responses.entries) {
      if (Uri.parse(url).path.endsWith(entry.key) ||
          url.contains(entry.key)) {
        return entry.value;
      }
    }
    return const LocalazeResponse(status: 404);
  }
}

/// In-memory storage, so a test never touches the disk.
class FakeStorage implements LocalazeStorage {
  FakeStorage({this.asset, this.cache, this.writable = true});

  String? asset;
  String? cache;
  bool writable;

  /// Set to throw from [readAsset] or [readCache], for the unreadable cases.
  Object? throwOnRead;

  int writes = 0;

  @override
  Future<String?> readAsset(String language) async {
    final failure = throwOnRead;
    if (failure != null) throw failure;
    return asset;
  }

  @override
  Future<String?> readCache(String language) async {
    final failure = throwOnRead;
    if (failure != null) throw failure;
    return cache;
  }

  @override
  Future<bool> writeCache(String language, String body) async {
    if (!writable) return false;
    writes++;
    cache = body;
    return true;
  }
}

/// Collects diagnostics so a test can assert something was reported.
class Reported {
  final List<String> messages = <String>[];
  final List<Object?> errors = <Object?>[];

  void call(String message, Object? error) {
    messages.add(message);
    errors.add(error);
  }

  bool mentions(String fragment) =>
      messages.any((message) => message.contains(fragment));

  bool get isEmpty => messages.isEmpty;
}

/// Loads a file from `../contract/fixtures`.
///
/// One fixture project, shared by all three packages. A Dart-only copy would
/// drift from Swift's and Kotlin's within a release.
String fixture(String path) =>
    File('${Directory.current.path}/../contract/fixtures/$path')
        .readAsStringSync();
