/// The generated code, compiled against this package, rendering the fixture.
///
/// This is the `LZ-54` guarantee for generation: the three generators agree
/// because their output renders the same strings, not because their source
/// looks alike. See `contract/generator-contract.md` §9.
library;

import 'dart:convert';

import 'package:localaze/localaze.dart';
import 'package:test/test.dart';

import '../fakes/fakes.dart';
import 'golden/localaze.g.dart';

Localaze _translations(String locale) =>
    Localaze.forLocale(locale, const LocalazeConfig(apiKey: 'test-key'));

/// Calls the typed accessor for [key], the way an app would.
String _render(Localaze t, String key, Map<String, Object?> args) =>
    switch (key) {
      'auth.sign_out' => t.authSignOut,
      'auth.welcome' => t.authWelcome(name: args['name']! as String),
      'billing.due' =>
        t.billingDue(when: DateTime.parse(args['when']! as String)),
      'inbox.unread' => t.inboxUnread(count: args['count']! as num),
      _ => throw ArgumentError('No accessor for $key'),
    };

void main() {
  final renders = (jsonDecode(fixture('expected-renders.json'))
          as Map<String, Object?>)['renders']! as List<Object?>;

  test('generator.renders-all — every expected render, through accessors', () {
    for (final row in renders.cast<Map<String, Object?>>()) {
      final locale = row['locale']! as String;
      final key = row['key']! as String;
      expect(
        _render(_translations(locale), key, row['args']! as Map<String, Object?>),
        row['expect'],
        reason: '$locale $key ${row['args']}',
      );
    }
  });

  test('generator.typed-accessors — the generated constants', () {
    expect(Localaze.supportedLocales, <String>['az', 'ru']);
    expect(Localaze.sourceLocale, 'az');
    expect(Localaze.generatedFrom, '1.0.0');
  });

  test('generator.plural-guard — extreme selectors render the catch-all', () {
    final ru = _translations('ru');
    const other = 'сообщения';
    for (final value in <num>[double.infinity, double.nan, 1e15, -1e16]) {
      expect(ru.inboxUnread(count: value), endsWith(other), reason: '$value');
    }
    expect(ru.inboxUnread(count: 1.5), 'У вас 1.5 сообщения');
  });

  test('a locale the release does not carry starts from the source language',
      () {
    expect(_translations('en').authSignOut, 'Cixis');
  });
}
