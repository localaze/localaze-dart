/// Drives the demo's widgets against a fake transport.
///
/// `flutter analyze` says the app compiles; these say it works. Every scenario
/// the Server panel offers is exercised here through the real widget tree and
/// the real `LocalazeController`, so the Flutter binding is covered rather than
/// assumed.
///
/// No network: the fake transport means these run in CI and on a plane.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localaze_demo/localaze.g.dart';
import 'package:localaze_flutter/localaze_flutter.dart';

/// Serves whatever it is told to, recording what was asked.
class FakeTransport implements LocalazeTransport {
  FakeTransport(this.responses);

  final Map<String, LocalazeResponse> responses;
  final List<String> urls = <String>[];

  @override
  Future<LocalazeResponse> get(String url, Map<String, String> headers) async {
    urls.add(url);
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) return entry.value;
    }
    return const LocalazeResponse(status: 404);
  }
}

LocalazeResponse ok(String body) => LocalazeResponse(status: 200, body: body);

String versionBody(String version) =>
    '{"environment":"demo","version":"$version","bump":"PATCH","keyCount":4}';

/// A ru catalog at [version] whose sign-out reads [signOut].
///
/// [countType] is what makes the retype case reachable: `STRING` here is a
/// catalog that kept the key and the parameter name but changed its type.
String catalog(
  String version, {
  String signOut = 'Выход',
  String countType = 'NUMBER',
}) =>
    '''
{"version":"$version","language":"ru","messages":{
"auth.sign_out":{"selectors":[],"params":[],"variants":{"*":[{"text":"$signOut"}]}},
"auth.welcome":{"selectors":[],"params":[{"name":"name","type":"STRING"}],
  "variants":{"*":[{"text":"Добро пожаловать, "},{"var":"name","type":"STRING"}]}},
"billing.due":{"selectors":[],"params":[{"name":"when","type":"DATETIME"}],
  "variants":{"*":[{"text":"Оплата до "},{"var":"when","type":"DATETIME"}]}},
"inbox.unread":{"selectors":["count"],"params":[{"name":"count","type":"$countType"}],
  "variants":{
    "one":[{"text":"У вас "},{"var":"count","type":"$countType"},{"text":" сообщение"}],
    "few":[{"text":"У вас "},{"var":"count","type":"$countType"},{"text":" сообщения"}],
    "many":[{"text":"У вас "},{"var":"count","type":"$countType"},{"text":" сообщений"}],
    "*":[{"text":"У вас "},{"var":"count","type":"$countType"},{"text":" сообщения"}]}}}}
''';

/// A controller wired the way `main.dart` wires one, minus the widgets.
LocalazeController<Localaze> controllerFor({
  required String locale,
  LocalazeTransport? transport,
  LocalazeUpdatePolicy policy = LocalazeUpdatePolicy.minorAndPatch,
  void Function(String, Object?)? onDiagnostic,
}) {
  return LocalazeController<Localaze>(
    initialLocale: locale,
    supportedLocales: Localaze.supportedLocales,
    runtimeOf: (translations) => translations.runtime,
    create: (locale) => Localaze.forLocale(
      locale,
      LocalazeConfig(
        apiKey: 'demo-key',
        baseUrl: 'http://stub',
        policy: policy,
        applyImmediately: true,
        transport: transport,
        onDiagnostic: onDiagnostic,
      ),
    ),
  );
}

void main() {
  group('generated accessors', () {
    test('render from the compiled-in catalog with no network or assets', () {
      // The offline-first-launch case: a fresh install with nothing.
      final az = controllerFor(locale: 'az').translations;

      expect(az.authSignOut, 'Cixis');
      expect(az.authWelcome(name: 'Ayan'), 'Xos geldiniz, Ayan');
      expect(az.billingDue(when: DateTime.utc(2026, 3, 1)),
          'Odenis 2026-03-01T00:00:00Z tarixindedir');
      expect(az.inboxUnread(count: 3), '3 mesaj');
    });

    test('compile the Russian plural rule, including the 11 exception', () {
      final ru = controllerFor(locale: 'ru').translations;

      // The rows the demo's chips offer, and the reason the rule is generated
      // rather than guessed.
      expect(ru.inboxUnread(count: 1), 'У вас 1 сообщение');
      expect(ru.inboxUnread(count: 2), 'У вас 2 сообщения');
      expect(ru.inboxUnread(count: 5), 'У вас 5 сообщений');
      expect(ru.inboxUnread(count: 11), 'У вас 11 сообщений');
      expect(ru.inboxUnread(count: 21), 'У вас 21 сообщение');
      expect(ru.inboxUnread(count: 101), 'У вас 101 сообщение');
      expect(ru.inboxUnread(count: 111), 'У вас 111 сообщений');
    });
  });

  group('controller', () {
    test('switches locale without a restart and notifies', () async {
      final controller = controllerFor(locale: 'az');
      var notified = 0;
      controller.addListener(() => notified++);

      expect(controller.translations.authSignOut, 'Cixis');

      await controller.setLocale('ru');

      expect(controller.translations.authSignOut, 'Выход');
      expect(notified, greaterThan(0));
    });

    test('ignores a locale the project does not have', () async {
      final controller = controllerFor(locale: 'az');
      await controller.setLocale('fr');

      expect(controller.locale, 'az');
    });

    test('applies a patch and rebuilds', () async {
      final transport = FakeTransport(<String, LocalazeResponse>{
        '/version': ok(versionBody('1.0.1')),
        '/translations': ok(catalog('1.0.1', signOut: 'Выйти')),
      });
      final controller = controllerFor(locale: 'ru', transport: transport);

      expect(controller.translations.authSignOut, 'Выход');

      final status = await controller.update();

      expect(status.outcome, LocalazeFetchOutcome.applied);
      expect(controller.translations.authSignOut, 'Выйти');
      expect(controller.version, '1.0.1');
    });

    test('refuses a major whatever the policy', () async {
      final transport = FakeTransport(<String, LocalazeResponse>{
        '/version': ok(versionBody('2.0.0')),
      });
      final controller = controllerFor(locale: 'ru', transport: transport);

      final status = await controller.update();

      expect(status.outcome, LocalazeFetchOutcome.refusedByPolicy);
      expect(controller.translations.authSignOut, 'Выход');
    });

    test('refuses a patch that retyped a parameter', () async {
      // The case the demo's "retyped" chip sets up. Policy accepts it, every
      // key is present, and the parameter is still called count.
      final transport = FakeTransport(<String, LocalazeResponse>{
        '/version': ok(versionBody('1.0.2')),
        '/translations':
            ok(catalog('1.0.2', signOut: 'Выйти', countType: 'STRING')),
      });
      final controller = controllerFor(locale: 'ru', transport: transport);

      final status = await controller.update();

      expect(status.outcome, LocalazeFetchOutcome.refusedBySignature);
      expect(status.detail, contains('inbox.unread.count'));
      // Refused whole: sign-out is fine in that catalog and still not taken.
      expect(controller.translations.authSignOut, 'Выход');
    });

    test('reports rather than throws when the server is down', () async {
      final reported = <String>[];
      final transport = FakeTransport(<String, LocalazeResponse>{
        '/version': const LocalazeResponse.failed('connection refused'),
      });
      final controller = controllerFor(
        locale: 'ru',
        transport: transport,
        onDiagnostic: (message, _) => reported.add(message),
      );

      final status = await controller.update();

      expect(status.outcome, LocalazeFetchOutcome.failed);
      expect(reported, isNotEmpty);
      expect(controller.translations.authSignOut, 'Выход');
    });

    test('makes no request at all under policy none', () async {
      final transport = FakeTransport(<String, LocalazeResponse>{
        '/version': ok(versionBody('1.0.1')),
      });
      final controller = controllerFor(
        locale: 'ru',
        transport: transport,
        policy: LocalazeUpdatePolicy.none,
      );

      await controller.update();

      expect(transport.urls, isEmpty);
    });
  });

  group('LocalazeScope', () {
    testWidgets('puts translations in the tree and rebuilds on locale change',
        (tester) async {
      final controller = controllerFor(locale: 'az');

      await tester.pumpWidget(LocalazeScope<Localaze>(
        controller: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Text(LocalazeScope.of<Localaze>(context).authSignOut),
            ),
          ),
        ),
      ));

      expect(find.text('Cixis'), findsOneWidget);

      await controller.setLocale('ru');
      await tester.pump();

      expect(find.text('Выход'), findsOneWidget);
      expect(find.text('Cixis'), findsNothing);
    });

    testWidgets('rebuilds when an applied catalog changes the wording',
        (tester) async {
      // The property a LocalizationsDelegate alone cannot provide: the locale
      // did not change, the content did.
      final transport = FakeTransport(<String, LocalazeResponse>{
        '/version': ok(versionBody('1.0.1')),
        '/translations': ok(catalog('1.0.1', signOut: 'Выйти')),
      });
      final controller = controllerFor(locale: 'ru', transport: transport);

      await tester.pumpWidget(LocalazeScope<Localaze>(
        controller: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Text(LocalazeScope.of<Localaze>(context).authSignOut),
            ),
          ),
        ),
      ));

      expect(find.text('Выход'), findsOneWidget);

      await controller.update();
      await tester.pump();

      expect(find.text('Выйти'), findsOneWidget);
    });
  });
}
