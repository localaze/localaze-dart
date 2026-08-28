/// Catalogs on disk. The only filesystem code in the package.
library;

import 'dart:convert';
import 'dart:io';

import '../storage.dart';

/// Reads bundled catalogs from [assetDirectory] and caches applied ones in
/// [cacheDirectory].
///
/// [cacheDirectory] is optional. Left null, updates apply for the session only,
/// which is the documented default: this package has no dependency that can
/// find a writable directory on its own, and adding one would push it onto
/// every consuming app.
class LocalazeFileStorage implements LocalazeStorage {
  const LocalazeFileStorage({
    this.assetDirectory = 'assets/localaze',
    this.cacheDirectory,
  });

  final String assetDirectory;
  final String? cacheDirectory;

  @override
  Future<String?> readAsset(String language) =>
      _read('$assetDirectory/$language.json');

  @override
  Future<String?> readCache(String language) {
    final directory = cacheDirectory;
    if (directory == null) return Future.value(null);
    return _read('$directory/$language.json');
  }

  @override
  Future<bool> writeCache(String language, String body) async {
    final directory = cacheDirectory;
    if (directory == null) return false;

    try {
      final folder = Directory(directory);
      if (!await folder.exists()) await folder.create(recursive: true);
      await File('$directory/$language.json')
          .writeAsString(body, encoding: utf8, flush: true);
      return true;
    } catch (_) {
      // Reported by the updater, which knows whether it mattered.
      return false;
    }
  }

  /// Null for anything unreadable, including a corrupt or truncated file.
  ///
  /// A missing asset is expected rather than exceptional — the compiled-in copy
  /// sits behind it — so there is nothing to distinguish here.
  Future<String?> _read(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsString(encoding: utf8);
    } catch (_) {
      return null;
    }
  }
}
