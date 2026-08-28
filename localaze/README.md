# localaze-dart

The Localaze runtime for Dart and Flutter. `LZ-55`.

Generated code gives an app typed accessors. This package gives it everything else: fetching a newer catalog, caching it, deciding whether it is safe to apply, and rendering a message from it.

> **Implemented.** 107 tests pass against the shared fixture project. Run them with `dart test`.

## Baselines

Chosen rather than confirmed — the app teams delegated the call. Reasoning is in `CLAUDE.md`, and each is a one-line change.

- Dart SDK `^3.5.0`
- **No Flutter dependency.** The core is pure Dart, so `dart test` needs no Flutter install and a CLI or server consumer carries no UI framework
- **Zero runtime dependencies**
- Flutter Web works, because `dart:io` sits behind the separate `package:localaze/io.dart` entry point

## Intended use

```dart
final localaze = Localaze(
  locale: 'ru',
  config: LocalazeConfig(apiKey: '...'),
);

localaze.authSignOut;                  // 'Выход'
localaze.authWelcome(name: 'Аян');     // 'Добро пожаловать, Аян'
localaze.inboxUnread(count: 11);       // 'У вас 11 сообщений'
localaze.inboxUnread();                // compile error — a plural needs its count
localaze.inboxUnread(count: 'eleven'); // compile error — count is numeric
```

The last two lines are the point of the whole SDK. A missing or wrongly typed translation argument is caught by the compiler, not by a user reading a broken screen.

Updating is explicit and never blocks a screen:

```dart
await localaze.update();   // fetches, checks, applies per policy. Never throws.
```

## Configuration

Every option has a default except the key.

```dart
LocalazeConfig(
  apiKey: '...',                                // required; carries project and environment
  baseUrl: 'https://localize.sharpy.dev',
  assetPath: 'assets/localaze',
  cacheDirectory: null,                         // see below
  policy: LocalazeUpdatePolicy.minorAndPatch,
  timeout: const Duration(seconds: 10),
  applyImmediately: false,
  onDiagnostic: (message, error) => log(message),
)
```

**`cacheDirectory` is unset by default, so an applied update lasts for the session only.** This package has no dependency that can find a writable directory on its own, and adding one would push it onto every consumer. Pass a directory — from `path_provider` or wherever your app already gets one — to make updates survive a restart.

**Pass `onDiagnostic` during integration.** Nothing here throws, which means a wrong API key and a quiet network look identical from the outside. The callback is how you find out an integration never worked.

## What it will not do

- **It never throws.** Network failure, malformed payload, unreadable cache, missing asset, refused update — each leaves your app on the text it already had. A translation outage should be a stale screen, not a crash.
- **It never parses MF2.** Catalogs arrive already parsed. This is what makes the SDK possible without a Dart MF2 library, which does not exist (decision D7).
- **It never applies a major update**, whatever the policy says. A major is signature-breaking by definition, so its messages no longer take the parameters your call sites pass.
- **It never applies half a catalog.** An incompatible catalog is refused whole, because half an update means some screens render text the compiler never checked.

## Reading order

1. `../contract/runtime-contract.md` — the behaviour, specified once for all three platforms
2. `CLAUDE.md` — what is specific to Dart, and the defects in the current inlined runtime to fix while lifting it
3. `../contract/conformance.json` — every case this package must pass
