/// `Localizations` integration, so `BuildContext` lookup works the way Flutter
/// developers expect (`LZ-55`).
library;

import 'package:flutter/widgets.dart';

import 'controller.dart';

/// Puts the current locale's translations into the tree.
///
/// Wrap the app once:
///
/// ```dart
/// LocalazeScope<Localaze>(
///   controller: controller,
///   child: MaterialApp(...),
/// )
/// ```
///
/// and read them anywhere below with `LocalazeScope.of<Localaze>(context)`.
///
/// An `InheritedNotifier` rather than a `LocalizationsDelegate`, and the choice
/// is worth stating. A delegate loads per `Locale` and is rebuilt when the
/// locale changes, which covers half of what is needed here — but an applied
/// over-the-air catalog changes the *content* without changing the locale, and
/// a delegate has no way to say so. Listening to the controller covers both.
///
/// [LocalazeDelegate] is still provided for apps that want the delegate wired
/// into `MaterialApp.localizationsDelegates` as well.
class LocalazeScope<T> extends InheritedNotifier<LocalazeController<T>> {
  const LocalazeScope({
    super.key,
    required LocalazeController<T> controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller for the nearest scope.
  ///
  /// Throws when there is none, deliberately: that is a wiring mistake in the
  /// app, caught on the first frame, not a runtime condition the SDK's
  /// no-throw rule is about. The rule protects against a translation outage
  /// becoming a crash; it does not ask the package to paper over a missing
  /// widget.
  static LocalazeController<T> controllerOf<T>(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LocalazeScope<T>>();

    assert(scope != null, 'No LocalazeScope<$T> above this widget. '
        'Wrap your app in LocalazeScope<$T>(controller: ..., child: ...).');

    return scope!.notifier!;
  }

  /// The generated translations for the current locale.
  static T of<T>(BuildContext context) => controllerOf<T>(context).translations;
}

/// A `LocalizationsDelegate` over the same controller.
///
/// Optional. [LocalazeScope] alone is enough, and is what rebuilds the tree
/// when a catalog is applied. This exists so `Localizations.of<T>(context, T)`
/// also works, which some apps and packages expect.
class LocalazeDelegate<T> extends LocalizationsDelegate<T> {
  const LocalazeDelegate(this.controller);

  final LocalazeController<T> controller;

  @override
  bool isSupported(Locale locale) =>
      controller.supportedLocales.contains(locale.languageCode);

  @override
  Future<T> load(Locale locale) async {
    await controller.setLocale(locale.languageCode);
    return controller.translations;
  }

  /// Reloaded whenever the delegate instance changes, which is how a locale
  /// switch reaches `Localizations`.
  @override
  bool shouldReload(covariant LocalazeDelegate<T> old) =>
      old.controller.locale != controller.locale;
}
