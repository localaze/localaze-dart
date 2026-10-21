# localaze-dart

The Localaze runtime for Dart and Flutter. `LZ-55`.

Generated code gives an app typed accessors. This package gives it everything else: fetching a newer catalog, caching it, deciding whether it is safe to apply, and rendering a message from it.

It also ships the generator that writes those accessors from a published release.

> **Implemented.** 134 tests pass against the shared fixture project. Run them with `dart test`.

## Baselines

Chosen rather than confirmed — the app teams delegated the call. Reasoning is in `CLAUDE.md`, and each is a one-line change.

- Dart SDK `^3.5.0`
- **No Flutter dependency.** The core is pure Dart, so `dart test` needs no Flutter install and a CLI or server consumer carries no UI framework
- **Zero runtime dependencies**
- Flutter Web works, because `dart:io` sits behind the separate `package:localaze/io.dart` entry point

## Generating

Run from the app's root, with an integration key from the project's settings:

```
dart run localaze:generate --key $LOCALAZE_KEY --version 1.4.0
```

That writes two things:

| Output | Default | Contents |
|---|---|---|
| `--out` | `lib/localaze.g.dart` | The `Localaze` class: typed accessors, the signature, plural rules, and a compiled-in copy of every catalog |
| `--assets` | `assets/localaze/` | One `<language>.json` per language, to declare under `flutter: assets:` |

**Pin `--version` in a build.** Without it the generator takes the environment's live release, so two builds of the same commit could differ. Commit the generated file: it is deterministic, so regenerating unchanged content produces no diff.

Generation fails, naming every problem at once, when a translation is missing, a catalog is from a different release, or a key cannot become a Dart name. `--allow-gaps` turns missing translations into warnings for early development.

For a build with no network, save the server's responses and replay them:

```
dart run localaze:generate --manifest manifest.json --catalogs catalogs/
```

The full specification is `../contract/generator-contract.md`.

## Using it

```dart
final t = Localaze.forLocale('ru', LocalazeConfig(
  apiKey: '...',
  transport: LocalazeIoTransport(),   // from package:localaze/io.dart
));

t.authSignOut;                  // 'Выход'
t.authWelcome(name: 'Аян');     // 'Добро пожаловать, Аян'
t.inboxUnread(count: 11);       // 'У вас 11 сообщений'
t.inboxUnread();                // compile error — a plural needs its count
t.inboxUnread(count: 'eleven'); // compile error — count is numeric
```

The last two lines are the point of the whole SDK. A missing or wrongly typed translation argument is caught by the compiler, not by a user reading a broken screen.

Updating is explicit and never blocks a screen:

```dart
await t.runtime.update();   // fetches, checks, applies per policy. Never throws.
```

A Flutter app uses `package:localaze_flutter` on top, which wires `Localizations`, locale switching and asset loading.

## Configuration

Every option has a default except the key.

```dart
LocalazeConfig(
  apiKey: '...',                                // required; carries project and environment
  baseUrl: 'https://localize.sharpy.dev',
  policy: LocalazeUpdatePolicy.minorAndPatch,
  timeout: const Duration(seconds: 10),
  applyImmediately: false,
  dateFormatter: localazeIsoUtc,
  onDiagnostic: (message, error) => log(message),
  transport: null,                              // see below
  storage: null,
)
```

**Transport and storage are injected.** The core never imports `dart:io`, so it runs on Flutter Web. `package:localaze/io.dart` provides `LocalazeIoTransport` and `LocalazeFileStorage` for every other platform. With no storage, an applied update lasts for the session only.

**Pass `onDiagnostic` during integration.** Nothing here throws, which means a wrong API key and a quiet network look identical from the outside. The callback is how you find out an integration never worked.

## What it will not do

- **It never throws.** Network failure, malformed payload, unreadable cache, missing asset, refused update — each leaves your app on the text it already had. A translation outage should be a stale screen, not a crash.
- **It never parses MF2.** Catalogs arrive already parsed. This is what makes the SDK possible without a Dart MF2 library, which does not exist (decision D7).
- **It never applies a major update**, whatever the policy says. A major is signature-breaking by definition, so its messages no longer take the parameters your call sites pass.
- **It never applies half a catalog.** An incompatible catalog is refused whole, because half an update means some screens render text the compiler never checked.

## Reading order

1. `../contract/runtime-contract.md` — the behaviour, specified once for all three platforms
2. `../contract/generator-contract.md` — what the generator emits and when it refuses
3. `CLAUDE.md` — what is specific to Dart
4. `../contract/conformance.json` — every case this package must pass
