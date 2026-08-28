/// Fetching, checking and applying catalogs.
///
/// Nothing here throws. Every failure path leaves the app on the catalog it
/// already had, because a translation outage must never become a crash.
///
/// See `../../contract/runtime-contract.md` sections 5, 6 and 8.
library;

import 'dart:convert';

import 'catalog.dart';
import 'config.dart';
import 'diagnostics.dart';
import 'signature.dart';
import 'storage.dart';
import 'transport.dart';
import 'version.dart';

class LocalazeUpdater {
  LocalazeUpdater({
    required this.config,
    required this.signature,
    required Diagnostics diagnostics,
    required LocalazeTransport? transport,
    required LocalazeStorage storage,
  })  : _diagnostics = diagnostics,
        _transport = transport,
        _storage = storage;

  final LocalazeConfig config;
  final LocalazeSignature signature;
  final Diagnostics _diagnostics;
  final LocalazeTransport? _transport;
  final LocalazeStorage _storage;

  /// Held per language, so an unchanged catalog costs a round trip and nothing
  /// else. The server's ETag is version-scoped, so a pinned version's tag never
  /// changes and a rollback returns the earlier tag rather than a new one.
  final Map<String, String> _etags = <String, String>{};

  /// What the key currently serves, or null if it cannot be read.
  ///
  /// Cheap enough for every launch: it does not download the translations.
  Future<String?> currentVersion() async {
    final response = await _get('/api/v1/read/version');
    if (response == null || !response.isOk) return null;

    final version = _stringField(response.body!, 'version');
    if (version == null) {
      _diagnostics.report('/api/v1/read/version carried no version');
    }
    return version;
  }

  /// Downloads [language] if the server has something this build accepts.
  ///
  /// The order is policy, version, download, signature, persist. Policy comes
  /// first because it is the cheapest way to answer the question, and the
  /// signature is checked before anything is written, because a refused catalog
  /// must leave no trace.
  Future<(LocalazeCatalog?, LocalazeFetchStatus)> fetchIfAccepted(
    String language,
    String held, {
    String? pinnedVersion,
  }) async {
    if (!config.policy.fetches) {
      return (
        null,
        const LocalazeFetchStatus(
          LocalazeFetchOutcome.refusedByPolicy,
          detail: 'policy none makes no request',
        )
      );
    }

    final available = pinnedVersion ?? await currentVersion();
    if (available == null) {
      return (null, _failed('The published version could not be read'));
    }

    if (!LocalazeVersion.accepts(held, available, config.policy)) {
      final detail = 'Version $available refused by policy '
          '${config.policy.name}, staying on $held';
      _diagnostics.report(detail);
      return (
        null,
        LocalazeFetchStatus(LocalazeFetchOutcome.refusedByPolicy,
            detail: detail, version: available)
      );
    }

    final path = '/api/v1/read/translations/$language?format=resolved'
        '${pinnedVersion == null ? '' : '&version=$pinnedVersion'}';

    final response = await _get(path, etag: _etags[language]);
    if (response == null) {
      return (null, _failed('The $language catalog could not be fetched'));
    }

    if (response.isNotModified) {
      return (
        null,
        LocalazeFetchStatus(LocalazeFetchOutcome.upToDate,
            detail: 'not modified', version: held)
      );
    }

    if (!response.isOk) {
      // The status goes in the message on purpose: a 401 is a wrong key and
      // must be distinguishable from a quiet network by whoever reads the log.
      return (null, _failed('$path returned ${response.status}'));
    }

    final catalog =
        LocalazeCatalog.parse(response.body!, fallbackVersion: available);
    if (catalog == null || catalog.isEmpty) {
      return (null, _failed('The $language catalog had no readable messages'));
    }

    // Belt and braces. LZ-62 guarantees a minor or patch release is
    // signature-compatible, so a failure here is a platform bug rather than an
    // expected refusal — which is why it is reported as its own outcome.
    final problems = signature.incompatibilities(catalog);
    if (problems.isNotEmpty) {
      final detail = 'Catalog ${catalog.version} is not compatible: '
          '${problems.join(', ')}';
      _diagnostics.report(detail);
      return (
        null,
        LocalazeFetchStatus(LocalazeFetchOutcome.refusedBySignature,
            detail: detail, version: catalog.version)
      );
    }

    final etag = response.etag;
    if (etag != null) _etags[language] = etag;

    final persisted = await _persist(language, response.body!);

    return (
      catalog,
      LocalazeFetchStatus(
        LocalazeFetchOutcome.applied,
        version: catalog.version,
        detail: persisted ? null : 'applied for this session only, not cached',
      )
    );
  }

  LocalazeFetchStatus _failed(String detail) {
    _diagnostics.report(detail);
    return LocalazeFetchStatus(LocalazeFetchOutcome.failed, detail: detail);
  }

  Future<bool> _persist(String language, String body) async {
    try {
      final written = await _storage.writeCache(language, body);
      if (!written) {
        _diagnostics.report('Could not cache the $language catalog; '
            'it applies for this session only');
      }
      return written;
    } catch (error) {
      _diagnostics.report('Could not cache the $language catalog', error);
      return false;
    }
  }

  Future<LocalazeResponse?> _get(String path, {String? etag}) async {
    final transport = _transport;
    if (transport == null) {
      _diagnostics.report('No transport configured; '
          'import package:localaze/io.dart or supply one');
      return null;
    }

    final headers = <String, String>{
      'X-Localaze-Key': config.apiKey,
      'Accept': 'application/json',
      if (etag != null) 'If-None-Match': etag,
    };

    try {
      final response = await transport.get('${config.baseUrl}$path', headers);
      if (response.error != null) {
        _diagnostics.report('$path failed', response.error);
        return null;
      }
      if (response.isOk && response.body == null) {
        _diagnostics.report('$path returned 200 with no body');
        return null;
      }
      return response;
    } catch (error) {
      // A transport is not supposed to throw. One supplied by an app might.
      _diagnostics.report('$path threw', error);
      return null;
    }
  }

  /// One top-level string field, or null for anything unreadable.
  ///
  /// The version endpoint returns no `messages`, so the catalog parser
  /// correctly rejects it and this reads the one field that matters instead.
  static String? _stringField(String body, String field) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final value = decoded[field];
        if (value is String) return value;
      }
    } catch (_) {
      // Malformed JSON is a null, not an exception.
    }
    return null;
  }
}
