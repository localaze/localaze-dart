# localaze

The Localaze runtime and generator for Dart: typed translations generated from a [Localaze](https://localize.sharpy.dev) release, and updated over the air. Pure Dart with no dependencies, so it runs in Flutter, on the web, in a CLI and on a server.

```dart
t.inboxUnread(count: 11); // У вас 11 сообщений
t.inboxUnread();          // does not compile: a plural needs its count
```

Flutter apps use [`localaze_flutter`](../localaze_flutter/) on top of it.

**Documentation:** [the repository README](https://github.com/localaze/localaze-dart#readme) covers installing, generating, using, updates, errors and every configuration option. A runnable example is in [`example/main.dart`](example/main.dart).

MIT licensed.
