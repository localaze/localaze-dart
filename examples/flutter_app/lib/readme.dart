// The Flutter code the README shows, analyzed by CI with the rest of this app.
//
// `localaze.g.dart` is what the generator writes for the contract's fixture
// project; an app's own file has its own accessors.

import 'package:flutter/material.dart';
import 'package:localaze/io.dart';
import 'package:localaze_flutter/localaze_flutter.dart';

import 'localaze.g.dart';

const String localazeKey = String.fromEnvironment('LOCALAZE_KEY');

// #region flutter-setup
final controller = LocalazeController<Localaze>(
  initialLocale: 'az',
  supportedLocales: Localaze.supportedLocales,
  runtimeOf: (t) => t.runtime,
  create: (locale) => Localaze.forLocale(
    locale,
    LocalazeConfig(
      apiKey: localazeKey,
      transport: LocalazeIoTransport(),
      storage: const LocalazeFileStorage(), // reads assets/localaze/, caches updates
      onDiagnostic: (message, error) => debugPrint('localaze: $message'),
    ),
  ),
);

void main() {
  controller.load();
  runApp(
    LocalazeScope<Localaze>(
      controller: controller,
      child: const MaterialApp(home: Inbox()),
    ),
  );
}
// #endregion flutter-setup

// #region flutter-use
class Inbox extends StatelessWidget {
  const Inbox({super.key});

  @override
  Widget build(BuildContext context) {
    final t = LocalazeScope.of<Localaze>(context); // rebuilds on a new catalog or locale
    return Scaffold(
      appBar: AppBar(title: Text(t.inboxUnread(count: 3))),
      body: TextButton(
        onPressed: () => controller.setLocale('ru'), // no restart
        child: Text(t.authSignOut),
      ),
    );
  }
}
// #endregion flutter-use

// #region flutter-update
Future<void> refreshTranslations() async {
  final status = await controller.update(); // never throws
  debugPrint('${status.outcome.name}, rendering ${controller.version}');
}
// #endregion flutter-update
