# localaze_flutter

The Flutter binding for [`localaze`](../localaze/): translations from a `BuildContext`, locale switching without a restart, and a tree that rebuilds when a new catalog is applied over the air.

```dart
final t = LocalazeScope.of<Localaze>(context);
Text(t.inboxUnread(count: 3));
```

**Documentation:** [the repository README](https://github.com/localaze/localaze-dart#readme). A complete app is in [`examples/flutter_app`](../examples/flutter_app/).

MIT licensed.
