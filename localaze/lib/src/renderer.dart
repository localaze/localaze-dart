/// Turning a resolved message and its arguments into a string.
///
/// The whole algorithm is: pick a variant, walk its parts, concatenate. If an
/// implementation needs more than that, the payload is wrong.
///
/// See `../../contract/runtime-contract.md` section 3.
library;

import 'catalog.dart';

/// How a `DATETIME` parameter becomes text.
typedef LocalazeDateFormatter = String Function(DateTime value);

/// ISO-8601, UTC, second precision: `2026-03-01T00:00:00Z`.
///
/// The default is deliberate and worth arguing with. Locale-aware formatting is
/// usually what an app wants, but Dart, Swift and Kotlin do not produce the
/// same string for a given locale, so making it the default would break the one
/// guarantee these SDKs exist to make. This is identical on all three and
/// therefore testable. An app that wants a local format supplies one, and
/// accepts that it now owns the difference.
///
/// Written out rather than using [DateTime.toIso8601String], which appends
/// milliseconds and would make the three platforms disagree again.
String localazeIsoUtc(DateTime value) {
  final utc = value.toUtc();
  String pad(int number, [int width = 2]) =>
      number.toString().padLeft(width, '0');

  return '${pad(utc.year, 4)}-${pad(utc.month)}-${pad(utc.day)}'
      'T${pad(utc.hour)}:${pad(utc.minute)}:${pad(utc.second)}Z';
}

/// Renders [parts], substituting from [args].
///
/// A missing argument cannot happen through generated code, which requires
/// every parameter at the call site. It is handled anyway, as the empty string,
/// because the alternative is throwing and nothing in this package throws.
String localazeRender(
  List<LocalazePart> parts,
  Map<String, Object?> args, {
  LocalazeDateFormatter dateFormatter = localazeIsoUtc,
}) {
  final out = StringBuffer();

  for (final part in parts) {
    final text = part.text;
    if (text != null) {
      out.write(text);
      continue;
    }

    final name = part.variable;
    if (name == null) continue;

    out.write(_substitute(args[name], part.type, dateFormatter));
  }
  return out.toString();
}

String _substitute(
  Object? value,
  LocalazeParamType? type,
  LocalazeDateFormatter dateFormatter,
) {
  if (value == null) return '';

  if (value is DateTime) return dateFormatter(value);

  // An integral double renders without a decimal point, so a count passed as
  // 3.0 reads as "3" here, in Swift and in Kotlin alike. Left to toString it
  // would be "3.0" on all three — consistent, but not what a count should look
  // like on a screen.
  if (value is num && value == value.roundToDouble() && value.isFinite) {
    return value.toInt().toString();
  }

  return '$value';
}
