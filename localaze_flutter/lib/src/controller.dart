/// Owns a runtime per locale and rebuilds the tree when content changes.
library;

import 'package:flutter/foundation.dart';
import 'package:localaze/localaze.dart';

/// Builds the generated translations class for one locale.
///
/// Generated code supplies this. It is a function rather than an interface
/// because the generated type is different in every project, and the binding
/// must not know its name.
typedef LocalazeFactory<T> = T Function(String locale);

/// Holds the current locale's translations and notifies when they change.
///
/// Two things change what an app renders, and both have to reach the widget
/// tree:
///
/// - the **locale**, which `LZ-55` requires be switchable without a restart
/// - the **catalog**, when an over-the-air update is applied
///
/// A [ChangeNotifier] covers both, and it is what a Flutter developer already
/// reaches for. Nothing here throws, in keeping with the rest of the SDK.
class LocalazeController<T> extends ChangeNotifier {
  LocalazeController({
    required LocalazeFactory<T> create,
    required String initialLocale,
    required this.supportedLocales,
    required LocalazeRuntime Function(T) runtimeOf,
  })  : _create = create,
        _runtimeOf = runtimeOf,
        _locale = initialLocale {
    _translations = _create(_locale);
  }

  final LocalazeFactory<T> _create;

  /// How to reach the runtime inside the generated class.
  ///
  /// Generated code exposes it; this package cannot name the type, so the app
  /// passes an accessor. One line in the generated file, and it keeps the
  /// binding independent of any project's key set.
  final LocalazeRuntime Function(T) _runtimeOf;

  final List<String> supportedLocales;

  String _locale;
  late T _translations;

  /// The generated translations for the current locale.
  T get translations => _translations;

  String get locale => _locale;

  LocalazeRuntime get runtime => _runtimeOf(_translations);

  /// The release currently rendering, so a screen can show it.
  String get version => runtime.version;

  LocalazeFetchStatus get lastFetch => runtime.lastFetch;

  /// Reads the bundled asset and any cached catalog for the current locale.
  Future<void> load() async {
    await runtime.load();
    notifyListeners();
  }

  /// Switches locale without a restart, as `LZ-55` requires.
  ///
  /// A locale the project does not have is ignored rather than throwing, and a
  /// fresh runtime is built so the new locale starts from its own bundled
  /// content rather than inheriting the old one's applied catalog.
  Future<void> setLocale(String locale) async {
    if (locale == _locale || !supportedLocales.contains(locale)) return;

    _locale = locale;
    _translations = _create(locale);
    await runtime.load();
    notifyListeners();
  }

  /// Fetches and, per policy, applies a newer catalog.
  ///
  /// Never throws and never blocks a screen: the app renders from what it has
  /// throughout, and this only tells the tree to rebuild once it is done.
  Future<LocalazeFetchStatus> update({String? pinnedVersion}) async {
    final status = await runtime.update(pinnedVersion: pinnedVersion);
    notifyListeners();
    return status;
  }

  /// Applies a catalog held back because `applyImmediately` is off.
  ///
  /// The seam an app chooses for itself — a navigation event, a return from
  /// background — rather than text changing under a user mid-screen.
  bool applyPending() {
    final applied = runtime.applyPending();
    if (applied) notifyListeners();
    return applied;
  }
}
