# flutter_app

A Flutter demo over `localaze` and `localaze_flutter`, exercising every feature.

## Run it

Start the stub server first:

```
cd ../../contract/stub-server && dart run serve.dart
```

Then:

```
flutter run
```

An **Android emulator** reaches the host at `10.0.2.2`, not `localhost`:

```
flutter run --dart-define=LOCALAZE_BASE_URL=http://10.0.2.2:8787
```

A physical device wants the machine's address. Web and iOS simulator work with the default.

## Tests

```
flutter test
```

11 tests drive the real widget tree against a fake transport — no network, so they run in CI. They cover the generated accessors, the plural rule, locale switching, and every acceptance and refusal the Server panel can set up, including that `LocalazeScope` rebuilds when an applied catalog changes the wording without the locale changing.

`flutter analyze` is clean and `flutter build web` succeeds.

## What to try

Set the Server panel to **`retyped`** and press Check for update.

It offers `1.0.2`, a patch. The policy accepts it. Every key is present. `inbox.unread` still declares a parameter called `count`. Only the *type* changed, `NUMBER` to `STRING` — and `localaze.g.dart` has already promised every call site a `num`.

The SDK refuses the whole catalog and the Diagnostics panel says why. A name-only signature check, which is what the first implementation did, takes it.

Then drag the count slider to **11**, in Russian. It reads *У вас 11 сообщений*, not *сообщение*.

## The app supplies its own transport

`lib/platform.dart` implements `LocalazeTransport` over `package:http` rather than using the `dart:io` default from `package:localaze/io.dart`.

That is not a workaround, it is the supported path and the reason the SDK takes an interface at all: `dart:io` does not exist on Flutter Web, so a web build must supply its own. Doing it here means this demo runs on every Flutter target.

Storage is asset-only, with no cache. Persisting would need `path_provider`, and the SDK deliberately does not depend on it — so an applied update lasts for the session, which is the documented default when no cache directory is configured. The app says so on screen.

## `localaze.g.dart` is generated

It is the real output of the Dart generator for the fixture release, and so are `assets/localaze/`. Regenerate it from the stub server, exactly as an app would from production:

```
dart run localaze:generate --key demo-key --version 1.0.0 --base-url http://localhost:8787
```

Or offline, from the shared fixtures:

```
dart run localaze:generate --manifest ../../contract/fixtures/manifest.json --catalogs ../../contract/fixtures/catalogs
```

Both produce the same file, byte for byte.

Two things it demonstrates that are easy to miss:

- `inboxUnread` **requires** its count, because the message selects on it. Deleting the argument is a compile error, which is `LZ-54`'s guarantee in one line.
- The Russian plural rule is Dart control flow, including the `i % 100 != 11` exclusion. No CLDR data ships and no MessageFormat is parsed on device.

## What this app changed in the SDK

`localaze_flutter` did not re-export `LocalazeResponse`, so an app could not write the transport a web build requires. Found while writing the tests.
