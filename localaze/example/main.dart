// The code the README shows, compiled and run by CI.
//
// `localaze.g.dart` beside this file is what `dart run localaze:generate`
// writes for the contract's fixture project, a small app with four messages in
// Azerbaijani and Russian. An app's own generated file has its own accessors;
// everything else here is the same.
//
// Run it with `dart run example/main.dart`. With no LOCALAZE_KEY it renders
// the compiled-in catalogs and reports that it could not fetch.

import 'dart:io';

import 'package:localaze/io.dart';
import 'package:localaze/localaze.dart';

import 'localaze.g.dart';

Future<void> main() async {
  // #region setup
  final t = Localaze.forLocale(
    'ru',
    LocalazeConfig(
      apiKey: Platform.environment['LOCALAZE_KEY'] ?? '',
      transport: LocalazeIoTransport(),
      storage: const LocalazeFileStorage(cacheDirectory: '.localaze'),
      onDiagnostic: (message, error) => stderr.writeln('localaze: $message'),
    ),
  );
  await t.runtime.load(); // the cached catalog, if an earlier run saved one
  // #endregion setup

  // #region use
  print(t.authSignOut); // Выход
  print(t.authWelcome(name: 'Аян')); // Добро пожаловать, Аян
  print(t.inboxUnread(count: 1)); // У вас 1 сообщение
  print(t.inboxUnread(count: 11)); // У вас 11 сообщений
  print(t.billingDue(when: DateTime.utc(2026, 3, 1)));

  // Neither of these compiles:
  // t.inboxUnread();                 a plural needs its count
  // t.inboxUnread(count: 'eleven');  the count is a number
  // #endregion use

  // #region update
  final status = await t.runtime.update(); // never throws
  if (status.isApplied) {
    print('now on ${t.runtime.version}');
  } else {
    print('still on ${t.runtime.version}: ${status.outcome.name}');
  }
  // #endregion update
}

/// Every option, with its default. Only the key is required.
LocalazeConfig everyOption(String key) {
  // #region config
  return LocalazeConfig(
    apiKey: key, // carries the project and the environment
    baseUrl: 'https://localize.sharpy.dev',
    policy: LocalazeUpdatePolicy.minorAndPatch,
    timeout: const Duration(seconds: 10),
    applyImmediately: false,
    dateFormatter: localazeIsoUtc,
    onDiagnostic: null,
    transport: null, // no network: LocalazeIoTransport() from io.dart
    storage: null, // updates last for the session: LocalazeFileStorage()
  );
  // #endregion config
}
