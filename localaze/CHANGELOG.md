# Changelog

Versions follow `../RELEASING.md`: the Dart, Swift and Kotlin packages release together, at the same version.

## 0.1.0 — unreleased

First release.

- The runtime: fetches, caches and applies catalogs under an update policy and a names-and-types signature check, renders messages, and never throws. Pure Dart; `package:localaze/io.dart` adds the `dart:io` transport and storage.
- `dart run localaze:generate`: typed accessors and catalogs from a published release, per `../contract/generator-contract.md`.
