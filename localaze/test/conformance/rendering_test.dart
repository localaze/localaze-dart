/// Conformance group: rendering. Contract section 3.
library;

import 'dart:convert';

import 'package:localaze/localaze.dart';
import 'package:test/test.dart';

import '../fakes/fakes.dart';
import '../fakes/fixture_project.dart';

void main() {
  group('render.all — every row of expected-renders.json', () {
    // Driven from the shared fixture rather than repeated here, so Swift and
    // Kotlin assert against the identical set and a new case lands in all
    // three at once.
    final expected = jsonDecode(fixture('expected-renders.json')) as Map;
    final rows = (expected['renders'] as List).cast<Map<String, dynamic>>();

    for (final row in rows) {
      final locale = row['locale'] as String;
      final key = row['key'] as String;
      final args = (row['args'] as Map).cast<String, Object?>();
      final want = row['expect'] as String;

      test('$locale $key ${jsonEncode(args)} -> "$want"', () {
        final runtime = runtimeFor(locale);
        final resolved = _coerce(args);

        expect(
          runtime.render(key,
              args: resolved, selector: resolved['count'] as num?),
          want,
        );
      });
    }

    test('covers all four keys in both locales', () {
      // A guard on the fixture itself: a row silently dropped would make this
      // whole group pass while testing less.
      expect(rows.length, greaterThanOrEqualTo(20));
      expect(rows.map((r) => r['key']).toSet(),
          {'auth.sign_out', 'auth.welcome', 'billing.due', 'inbox.unread'});
      expect(rows.map((r) => r['locale']).toSet(), {'az', 'ru'});
    });
  });

  test('render.missing-category-falls-back', () {
    // A ru catalog whose inbox.unread has only `one` and `*`. Count 5 resolves
    // to `many`, which is absent, so `*` must answer. LZ-07 guarantees `*` is
    // always there, which is what makes this safe rather than optimistic.
    final runtime = runtimeFor('ru', compiledIn: fixture('bundled/partial-ru.json'));

    expect(runtime.render('inbox.unread', args: {'count': 5}, selector: 5),
        'У вас 5 сообщения');
  });

  test('render.malformed-part-skipped', () {
    const body = '''
    {"version":"1.0.0","messages":{"a.b":{"selectors":[],"params":[],
     "variants":{"*":[{"text":"before "},{"note":"neither"},{"text":"after"}]}}}}''';

    final catalog = LocalazeCatalog.parse(body);
    final parts = catalog!.messages['a.b']!.partsFor(null)!;

    expect(localazeRender(parts, const {}), 'before after');
  });

  group('date rendering', () {
    test('defaults to ISO-8601 UTC at second precision', () {
      // Not toIso8601String, which appends milliseconds and would put the three
      // platforms back out of step.
      expect(localazeIsoUtc(DateTime.utc(2026, 3, 1)), '2026-03-01T00:00:00Z');
      expect(localazeIsoUtc(DateTime.utc(2026, 12, 31, 23, 59, 59)),
          '2026-12-31T23:59:59Z');
    });

    test('converts a local time to UTC first', () {
      final local = DateTime.utc(2026, 3, 1, 12).toLocal();
      expect(localazeIsoUtc(local), '2026-03-01T12:00:00Z');
    });

    test('an app-supplied formatter wins', () {
      final runtime = runtimeFor(
        'az',
        config: LocalazeConfig(
          apiKey: 'k',
          dateFormatter: (value) => '${value.day}/${value.month}',
        ),
      );

      expect(runtime.render('billing.due', args: {'when': DateTime.utc(2026, 3, 1)}),
          'Odenis 1/3 tarixindedir');
    });
  });

  group('number substitution', () {
    test('an integral double has no decimal point', () {
      // 3.0 must read as "3" here, in Swift and in Kotlin alike. Left to
      // toString it would be "3.0" on all three: consistent, but not what a
      // count should look like on a screen.
      final runtime = runtimeFor('az');
      expect(runtime.render('inbox.unread', args: {'count': 3.0}, selector: 3.0),
          '3 mesaj');
    });

    test('a fractional value keeps its point', () {
      final runtime = runtimeFor('az');
      expect(runtime.render('inbox.unread', args: {'count': 2.5}, selector: 2.5),
          '2.5 mesaj');
    });
  });

  test('an unknown key renders the key and reports', () {
    final reported = Reported();
    final runtime = runtimeFor('az',
        config: LocalazeConfig(apiKey: 'k', onDiagnostic: reported.call));

    expect(runtime.render('nope.missing'), 'nope.missing');
    expect(reported.mentions('nope.missing'), isTrue);
  });
}

/// Fixture args are JSON, so a datetime arrives as a string.
Map<String, Object?> _coerce(Map<String, Object?> args) {
  return args.map((key, value) {
    if (key == 'when' && value is String) {
      return MapEntry(key, DateTime.parse(value));
    }
    return MapEntry(key, value);
  });
}
