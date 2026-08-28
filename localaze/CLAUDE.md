# localaze-dart

The Dart/Flutter runtime package. `LZ-55`.

Read `../CLAUDE.md` for the rules that govern every SDK package, and `../contract/runtime-contract.md` for the behaviour this one implements. This file records only what is specific to Dart.

## Baselines

**Not yet confirmed. Do not guess, and do not write `pubspec.yaml` until these are filled in.**

| | |
|---|---|
| Dart SDK constraint | `_to be confirmed_` |
| Flutter constraint | `_to be confirmed_` |
| Flutter Web supported | `_to be confirmed_` — see Transport below |
| Package name | `_to be confirmed_` — `localaze` or `localaze_sdk` |
| Distribution | Local path dependency for now. an internal pub registry is a later ticket |

Confirm with the first consuming app teams, who are the first consumers (`LZ-47`).

A constraint chosen by an assistant is a constraint every consuming app then has to unwind, which is the same reason `backend/CLAUDE.md` refuses to guess a Java version.

## Layout

```
localaze-dart/
├── CLAUDE.md
├── README.md
├── pubspec.yaml           blocked on Baselines
├── lib/
│   ├── localaze.dart      the only public export
│   └── src/
│       ├── config.dart          LocalazeConfig
│       ├── catalog.dart         LocalazeCatalog, parsing, part walking
│       ├── renderer.dart        variant selection and substitution
│       ├── signature.dart       names and types, compatibility check
│       ├── policy.dart          LocalazeUpdatePolicy, version comparison
│       ├── store.dart           resolution order: applied, cached, bundled, compiled-in
│       ├── updater.dart         currentVersion, fetchIfAccepted, ETag
│       ├── diagnostics.dart     the callback, and catching its throws
│       ├── transport.dart       the interface
│       ├── storage.dart         the interface
│       └── platform/            default implementations, the only place dart:io appears
└── test/
    ├── conformance/       one file per group in ../contract/conformance.json
    └── fakes/             FakeTransport, FakeStorage
```

`lib/localaze.dart` is the only public export. Everything under `src/` is private to the package until something outside needs it.

## Transport and storage

`lib/src/transport.dart` and `lib/src/storage.dart` are interfaces. **Core code never imports `dart:io`.**

This is not a style preference. `dart:io` is why the current generated runtime cannot run on Flutter Web and cannot be unit tested at all — `HttpClient` and `File` are constructed inline with no seam. Every failure row in contract §8 is reachable with a fake and unreachable without one.

`lib/src/platform/` holds the defaults and is the only directory permitted to import `dart:io`. If Flutter Web is in scope, it gets a conditional import there and nowhere else.

Prefer `package:http` over `dart:io`'s `HttpClient` for the default transport — it works on web, and it is what a Flutter team already has. Confirm the dependency before adding it.

## Defaults

| Option | Dart default |
|---|---|
| `assetPath` | `assets/localaze` — the app declares the same path in its own `pubspec.yaml` |
| `cacheDirectory` | Unset. The package has no dependency that can find a writable directory on its own, and adding `path_provider` would push a dependency onto every consumer. An app that wants persistence passes one |

`cacheDirectory` being unset means updates last for the session only. That is a documented default, not a failure, and `README.md` says so at the point an integrator would trip over it.

## Flutter integration

`LZ-55` requires `Localizations` integration so `BuildContext` lookup works the way Flutter developers expect, and locale switching at runtime without a restart.

Keep that in a separate `flutter/` entry point rather than in the core. A Dart-only consumer — a CLI, a server, a test — must not be forced to depend on Flutter. The core is pure Dart; the Flutter binding sits on top.

## Existing code to lift

`backend/localaze/src/main/resources/codegen/dart-ota-runtime.dart` is the closest thing to a working runtime today. **Lift it rather than rewrite it** — the config shape, the policy comparison and the diagnostic discipline are sound and hard-won.

Then fix what it gets wrong:

1. `localazeIncompatibilities` compares parameter **names only**. Contract §4 requires names and types. `../contract/fixtures/updates/retyped-1.0.2-ru.json` is the regression test.
2. `_get` never sends `If-None-Match`, though the server serves version-scoped ETags. Contract §6.
3. `dart:io` throughout, so no web and no tests. Contract §10.
4. There are no catalogs — translations are inlined into the generated file. Contract §1.
5. There is no per-key fallback, because there is only one source of content. Contract §7.
6. It is copied into every generated file, so fixing any of the above means every app regenerates. That is the reason this package exists.

## Never do

Everything in `../CLAUDE.md`, plus:

- Never import `dart:io` outside `lib/src/platform/`
- Never make the core depend on Flutter
- Never expose anything from `src/` without adding it to `lib/localaze.dart` deliberately
- Never add a dependency without confirming it. A package a consuming app must now carry is a cost, not a convenience
