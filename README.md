# Localaze for Dart and Flutter

Typed translations for Dart and Flutter apps, generated from a [Localaze](https://localize.sharpy.dev) release and updated over the air.

[![CI](https://github.com/localaze/localaze-dart/actions/workflows/ci.yml/badge.svg)](https://github.com/localaze/localaze-dart/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/v/tag/localaze/localaze-dart?label=version&sort=semver)](https://github.com/localaze/localaze-dart/tags)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Dart 3.5+](https://img.shields.io/badge/dart-3.5%2B-0175C2)
![Flutter 3.16+](https://img.shields.io/badge/flutter-3.16%2B-02569B)

| Package | What it is |
|---|---|
| [`localaze`](localaze/) | The runtime and the generator. Pure Dart, no dependencies: runs in Flutter, on the web, in a CLI or on a server |
| [`localaze_flutter`](localaze_flutter/) | The Flutter binding: translations from a `BuildContext`, and a tree that rebuilds when the locale changes or a new catalog arrives |

## Why

**A plural cannot be called without its count.** The generator turns every message into a typed accessor, so the compiler checks each call site:

<!-- snippet: localaze/example/main.dart#use -->
```dart
print(t.authSignOut); // Выход
print(t.authWelcome(name: 'Аян')); // Добро пожаловать, Аян
print(t.inboxUnread(count: 1)); // У вас 1 сообщение
print(t.inboxUnread(count: 11)); // У вас 11 сообщений
print(t.billingDue(when: DateTime.utc(2026, 3, 1)));

// Neither of these compiles:
// t.inboxUnread();                 a plural needs its count
// t.inboxUnread(count: 'eleven');  the count is a number
```

**A missing translation fails the build, not the screen.** Generation refuses a release in which any language lacks a message, and names every gap at once.

**Wording fixes reach users without an app release.** The app ships with every catalog compiled in, and fetches newer wording when you ask it to. A new catalog is applied only if every accessor the app was built with still fits it.

## Install

A git dependency on this repository at a release tag, until the packages are on pub.dev. A Flutter app needs only the binding, which brings the runtime with it:

```yaml
dependencies:
  localaze_flutter:
    git:
      url: https://github.com/localaze/localaze-dart.git
      path: localaze_flutter
      ref: 0.2.0
```

A Dart-only app uses `path: localaze` instead.

## Generate

From the app's root, with an integration key from the project's settings in Localaze:

```sh
dart run localaze:generate --key "$LOCALAZE_KEY" --version 1.4.0
```

Keep the key in an environment variable or your CI's secrets, never in the repository. The command writes:

| Output | Default | Check it in? |
|---|---|---|
| `--out` | `lib/localaze.g.dart` | **Yes.** Typed accessors, plural rules and a compiled-in copy of every catalog. Deterministic, so regenerating unchanged content gives no diff |
| `--assets` | `assets/localaze/` | **Yes.** One `<language>.json` per language; declare the folder under `flutter: assets:` |

**Pin `--version`.** Without it the generator takes the environment's live release, and two builds of the same commit could differ. Regenerate when keys change; wording changes need no regeneration.

Generation exits non-zero, listing every problem, when a translation is missing, a catalog is from a different release, or a key cannot become a Dart name. `--allow-gaps` turns missing translations into warnings for early development. `--manifest manifest.json --catalogs catalogs/` generates offline from saved responses.

## Use

In Flutter, put a controller at the top of the tree:

<!-- snippet: examples/flutter_app/lib/readme.dart#flutter-setup -->
```dart
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
```

and read the translations anywhere below it:

<!-- snippet: examples/flutter_app/lib/readme.dart#flutter-use -->
```dart
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
```

Without Flutter, create the translations directly:

<!-- snippet: localaze/example/main.dart#setup -->
```dart
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
```

## Updates over the air

Fetching is explicit, so it never blocks a screen. Call it on launch, on resume, or on a timer:

<!-- snippet: examples/flutter_app/lib/readme.dart#flutter-update -->
```dart
Future<void> refreshTranslations() async {
  final status = await controller.update(); // never throws
  debugPrint('${status.outcome.name}, rendering ${controller.version}');
}
```

Or, without Flutter:

<!-- snippet: localaze/example/main.dart#update -->
```dart
final status = await t.runtime.update(); // never throws
if (status.isApplied) {
  print('now on ${t.runtime.version}');
} else {
  print('still on ${t.runtime.version}: ${status.outcome.name}');
}
```

- **Offline**, the app renders the newest catalog it has: a cached update, else the bundled asset, else the compiled-in copy. A first launch with no network still shows every message.
- **The update policy** decides which releases are taken: `none`, `patchOnly`, `minorAndPatch` (the default) or a version range. A **major** release is never applied, whatever the policy, because its messages no longer fit the accessors the app was built with.
- **The signature check** applies a catalog only if every key the app knows is present with the same parameter names and types. An incompatible catalog is refused whole; half an update would mean screens the compiler never checked.
- **Wording changes need no regeneration.** Adding, removing or retyping a key does, and that is a new version of the app.

## Errors

Nothing in these packages throws, returns a failed future, or crashes the app. A network failure, a malformed payload, an unreadable cache or a refused update each leaves the app on the text it already had. A translation outage is a stale screen, not a crash.

The cost is that a wrong API key looks exactly like a quiet network. **Pass `onDiagnostic` while integrating**: it is called with a message naming what failed and why, for every failure that was swallowed.

```text
localaze: /api/v1/read/version returned 401
localaze: The published version could not be read
```

## Configuration

Every option has a default except the key:

<!-- snippet: localaze/example/main.dart#config -->
```dart
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
```

| Option | Default | What it does |
|---|---|---|
| `apiKey` | required | An integration key. It carries the project and the environment, so a staging build cannot read production |
| `baseUrl` | `https://localize.sharpy.dev` | Your Localaze server, if you run your own |
| `policy` | `minorAndPatch` | Which releases an update may apply |
| `timeout` | 10 seconds | Per request |
| `applyImmediately` | `false` | Apply a fetched catalog at once rather than on `applyPending()` or the next launch |
| `dateFormatter` | ISO-8601 UTC | How `DATETIME` parameters render |
| `onDiagnostic` | none | Called for every swallowed failure |
| `transport` | none | How to fetch. `LocalazeIoTransport()` from `package:localaze/io.dart`, or your own on the web |
| `storage` | none | Where to read bundled assets and cache updates. `LocalazeFileStorage()`; without it, updates last for the session |

The core never imports `dart:io`, which is why it runs on Flutter Web. `package:localaze/io.dart` holds the `dart:io` transport and storage for every other platform.

## Compatibility

| | |
|---|---|
| Dart | 3.5 or later |
| Flutter | 3.16 or later, for `localaze_flutter` |
| Platforms | Android, iOS, macOS, Windows, Linux, web |
| Localaze server | Any that serves `/api/v1/read/manifest` and `format=resolved` catalogs, which every release of Localaze does |

**One version across Dart, Swift and Kotlin.** The three SDKs implement one [contract](https://github.com/localaze/localaze-contract) and are released together, so `0.2.0` behaves the same on every platform. Versions are semantic; a change to what the generator writes counts as API. See [`RELEASING.md`](https://github.com/localaze/localaze-contract/blob/main/RELEASING.md).

## Links

- **Other platforms:** [Swift](https://github.com/localaze/localaze-swift) · [Kotlin and Android](https://github.com/localaze/localaze-kotlin)
- **The contract** all three implement: [localaze-contract](https://github.com/localaze/localaze-contract)
- **Changelogs:** [`localaze`](localaze/CHANGELOG.md) · [`localaze_flutter`](localaze_flutter/CHANGELOG.md)
- **A working app:** [`examples/flutter_app`](examples/flutter_app/), against the [stub read API](https://github.com/localaze/localaze-contract/tree/main/stub-server)
- **Problems:** [open an issue](https://github.com/localaze/localaze-dart/issues). Security issues: see [`SECURITY.md`](SECURITY.md)
- **Contributing:** [`CONTRIBUTING.md`](CONTRIBUTING.md)

MIT licensed. See [`LICENSE`](LICENSE).
