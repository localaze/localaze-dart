# localaze-dart

The Dart/Flutter runtime package, and its generator. `LZ-55`.

Read `../CLAUDE.md` for the rules that govern every SDK package, and `../contract/runtime-contract.md` for the behaviour this one implements. This file records only what is specific to Dart.

## Baselines

**Chosen, not confirmed.** The app teams were asked and delegated the decision, so these are recorded with their reasoning to make an override cheap. Each one is a single-line change plus a re-run of the suite.

| | | Why |
|---|---|---|
| Dart SDK | `^3.5.0` | Records, patterns and sealed classes without demanding a very recent SDK. Verified on 3.11.4 |
| Flutter | **Not a dependency** | See below |
| Flutter Web | Supported | The core is pure Dart; `dart:io` is confined to an opt-in entry point |
| Package name | `localaze` | |
| Runtime dependencies | **None** | |
| Distribution | Local path dependency. The internal pub registry is a later ticket | |

**The package does not depend on Flutter, and that is the load-bearing choice here.** A Flutter dependency would mean `flutter test` rather than `dart test`, a Flutter install in CI, and a Dart-only consumer — a CLI, a server, a conformance runner — carrying a UI framework it never calls. The core is pure Dart. A Flutter `Localizations` binding (`LZ-55`) sits on top later and depends on this, not the reverse.

**Zero runtime dependencies** for the same kind of reason: every package here is one a consuming app must also carry and keep in step. `dart:convert` covers JSON, and the default HTTP transport uses `dart:io`. An app wanting `package:http` injects it.

## Two entry points

```dart
import 'package:localaze/localaze.dart';  // pure Dart, web-safe, no dart:io
import 'package:localaze/io.dart';        // IoTransport and FileStorage
```

This split is what makes Flutter Web work. Anything reachable from `localaze.dart` that transitively imports `dart:io` breaks a web build, so the defaults live behind `io.dart` and a web app supplies its own transport and storage. It is also why the conformance tests can run without touching a socket.

## Layout

```
localaze-dart/
├── CLAUDE.md
├── README.md
├── pubspec.yaml
├── bin/
│   └── generate.dart      the generator command: network and files, nothing else
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
│       ├── platform/            default implementations, the only place dart:io appears in lib/
│       └── generator/           plan.dart decides and checks, dart_emitter.dart spells
└── test/
    ├── conformance/       one file per group in ../contract/conformance.json
    ├── generator/         the generator group, plus golden/localaze.g.dart
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

## The generator

`dart run localaze:generate`, specified in `../contract/generator-contract.md`.

- `lib/src/generator/` is pure Dart: it takes the manifest and catalogs as strings and returns a plan or every problem. Tests drive it directly.
- `bin/generate.dart` does the HTTP and the file writes, and is the only generator code that imports `dart:io`. `bin/` is not reachable from `package:localaze/localaze.dart`, so it costs a web build nothing.
- `lib/src/generator/` is not exported. An app runs the command; it never imports the generator.
- The golden file is `test/generator/golden/localaze.g.dart`. When generator output changes on purpose, run `UPDATE_GOLDEN=1 dart test test/generator` and review the diff like any other change.

## Never do

Everything in `../CLAUDE.md`, plus:

- Never import `dart:io` outside `lib/src/platform/` and `bin/`
- Never make the core depend on Flutter
- Never expose anything from `src/` without adding it to `lib/localaze.dart` deliberately
- Never add a dependency without confirming it. A package a consuming app must now carry is a cost, not a convenience
