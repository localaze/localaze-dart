/// The fixture project, wired up the way generated code would wire it.
///
/// The plural resolvers and signature here are hand-written copies of what the
/// generator emits for `Postbox`. That is the point: the runtime is exercised
/// through the same surface generated code uses, not through a back door.
library;

import 'package:localaze/localaze.dart';

import 'fakes.dart';

/// Compiled CLDR rules for Russian, as `PluralRuleCompiler` emits them.
///
/// The `i % 100 != 11` exclusion is the whole reason this is generated rather
/// than guessed: without it 11, 111 and 211 select `one` and read as
/// "У вас 11 сообщение".
String? russianPlural(num value) {
  final i = value.abs().floor();
  final v = value == i ? 0 : 1;

  if (v == 0 && (i % 10) == 1 && !((i % 100) == 11)) return 'one';
  if (v == 0 &&
      ((i % 10) >= 2 && (i % 10) <= 4) &&
      !((i % 100) >= 12 && (i % 100) <= 14)) {
    return 'few';
  }
  if (v == 0 &&
      ((i % 10) == 0 ||
          ((i % 10) >= 5 && (i % 10) <= 9) ||
          ((i % 100) >= 11 && (i % 100) <= 14))) {
    return 'many';
  }
  return null; // `other`, which is the catch-all.
}

/// Azerbaijani has one rule and no exception.
String? azerbaijaniPlural(num value) => value == 1 ? 'one' : null;

String? pluralFor(String locale, num value) =>
    locale == 'ru' ? russianPlural(value) : azerbaijaniPlural(value);

/// The signature the generator emits for the fixture project.
final LocalazeSignature fixtureSignature = LocalazeSignature.of({
  'auth.sign_out': const [],
  'auth.welcome': const [('name', 'STRING')],
  'billing.due': const [('when', 'DATETIME')],
  'inbox.unread': const [('count', 'NUMBER')],
});

String catalogFor(String locale) => fixture('catalogs/$locale.json');

/// A runtime configured the way generated code configures one.
LocalazeRuntime runtimeFor(
  String locale, {
  LocalazeConfig? config,
  String? compiledIn,
}) {
  return LocalazeRuntime(
    locale: locale,
    config: config ?? const LocalazeConfig(apiKey: 'test-key'),
    signature: fixtureSignature,
    compiledIn: compiledIn ?? catalogFor(locale),
    pluralResolver: (value) => pluralFor(locale, value),
  );
}

/// A response carrying a fixture file.
LocalazeResponse ok(String body, {String? etag}) =>
    LocalazeResponse(status: 200, body: body, etag: etag);

/// The `/version` endpoint's body. Note it carries no `messages`, which is why
/// the updater reads the field directly rather than through the catalog parser.
String versionBody(String version) => '''
{"environment":"production","version":"$version","bump":"PATCH",
 "note":null,"publishedAt":"2026-08-01T00:00:00Z","keyCount":4,
 "available":["1.0.0","$version"]}''';
