/// A demo that exercises every feature of the Localaze Flutter SDK.
///
/// Point it at the stub server in `../../contract/stub-server` (`dart run serve.dart`),
/// then use the Server panel to put a patch, a major, or a retyped catalog on
/// offer and watch the SDK accept or refuse it.
///
/// What each panel is for is written on the screen, so the app doubles as the
/// documentation for what the SDK does.
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:localaze_flutter/localaze_flutter.dart';

import 'localaze.g.dart';
import 'platform.dart';

/// Where the stub server is listening.
///
/// An Android emulator reaches the host through 10.0.2.2; a simulator, a
/// device on the same network, and web all want the machine's address.
const String baseUrl = String.fromEnvironment(
  'LOCALAZE_BASE_URL',
  defaultValue: 'http://localhost:8787',
);

/// The stub server's key. A real one carries the project and the environment.
const String apiKey = 'demo-key';

void main() => runApp(const DemoApp());

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  /// Every diagnostic the SDK reports.
  ///
  /// Nothing in the SDK throws, which means a wrong API key and a quiet network
  /// look identical from the outside. This panel is the whole reason the
  /// callback exists, so the demo shows it rather than hiding it in a log.
  final List<String> diagnostics = <String>[];

  LocalazeUpdatePolicy policy = LocalazeUpdatePolicy.minorAndPatch;
  bool applyImmediately = true;

  late LocalazeController<Localaze> controller;

  @override
  void initState() {
    super.initState();
    controller = _build();
    controller.load();
  }

  /// Rebuilt whenever a config option changes, because config is immutable.
  LocalazeController<Localaze> _build([String locale = 'az']) {
    return LocalazeController<Localaze>(
      initialLocale: locale,
      supportedLocales: Localaze.supportedLocales,
      runtimeOf: (translations) => translations.runtime,
      create: (locale) => Localaze.forLocale(
        locale,
        LocalazeConfig(
          apiKey: apiKey,
          baseUrl: baseUrl,
          policy: policy,
          applyImmediately: applyImmediately,
          transport: HttpTransport(),
          storage: const AssetStorage(),
          onDiagnostic: (message, error) {
            if (!mounted) return;
            setState(() => diagnostics.insert(
                0, error == null ? message : '$message — $error'));
          },
        ),
      ),
    );
  }

  void _reconfigure({LocalazeUpdatePolicy? newPolicy, bool? newApply}) {
    setState(() {
      policy = newPolicy ?? policy;
      applyImmediately = newApply ?? applyImmediately;

      final locale = controller.locale;
      controller.dispose();
      controller = _build(locale);
    });
    controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Localaze SDK demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Localaze's purple.
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF53278A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: LocalazeScope<Localaze>(
        controller: controller,
        child: DemoScreen(
          diagnostics: diagnostics,
          policy: policy,
          applyImmediately: applyImmediately,
          onPolicy: (value) => _reconfigure(newPolicy: value),
          onApplyImmediately: (value) => _reconfigure(newApply: value),
          onClearDiagnostics: () => setState(diagnostics.clear),
        ),
      ),
    );
  }
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({
    super.key,
    required this.diagnostics,
    required this.policy,
    required this.applyImmediately,
    required this.onPolicy,
    required this.onApplyImmediately,
    required this.onClearDiagnostics,
  });

  final List<String> diagnostics;
  final LocalazeUpdatePolicy policy;
  final bool applyImmediately;
  final ValueChanged<LocalazeUpdatePolicy> onPolicy;
  final ValueChanged<bool> onApplyImmediately;
  final VoidCallback onClearDiagnostics;

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  /// Drag this and watch the plural category change. The Russian rule is the
  /// interesting one: 11 and 111 select `many` despite ending in 1.
  double count = 1;

  String scenario = 'base';
  bool busy = false;
  LocalazeFetchStatus? lastStatus;

  @override
  Widget build(BuildContext context) {
    final controller = LocalazeScope.controllerOf<Localaze>(context);
    final t = controller.translations;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Localaze SDK'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Chip(
                label: Text('v${controller.version}'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _Panel(
            title: 'Rendered strings',
            subtitle: 'Every accessor is typed. inboxUnread cannot be called '
                'without a numeric count — that is a compile error, not a '
                'runtime one.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Line('authSignOut', t.authSignOut),
                _Line('authWelcome(name:)', t.authWelcome(name: 'Ayan')),
                _Line(
                  'billingDue(when:)',
                  t.billingDue(when: DateTime.utc(2026, 3, 1)),
                ),
                const SizedBox(height: 8),
                _Line('inboxUnread(count:)', t.inboxUnread(count: count)),
                Slider(
                  value: count,
                  min: 0,
                  max: 120,
                  divisions: 120,
                  label: count.toInt().toString(),
                  onChanged: (value) => setState(() => count = value),
                ),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final value in <int>[0, 1, 2, 5, 11, 21, 101, 111])
                      ActionChip(
                        label: Text('$value'),
                        onPressed: () =>
                            setState(() => count = value.toDouble()),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'In Russian, 11 and 111 select "many" despite ending in 1. '
                  'That rule is compiled into localaze.g.dart, so no CLDR data '
                  'ships and no MessageFormat is parsed on the device.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          _Panel(
            title: 'Locale',
            subtitle: 'Switches at runtime, with no restart.',
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'az', label: Text('Azərbaycan')),
                ButtonSegment<String>(value: 'ru', label: Text('Русский')),
              ],
              selected: <String>{controller.locale},
              onSelectionChanged: (selected) =>
                  controller.setLocale(selected.first),
            ),
          ),
          _Panel(
            title: 'Server',
            subtitle: 'Puts a release on offer. The stub server serves the same '
                'fixtures the conformance suites assert on.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final entry in _scenarios.entries)
                      ChoiceChip(
                        label: Text(entry.key),
                        selected: scenario == entry.key,
                        onSelected: (_) => _serve(entry.key),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _scenarios[scenario] ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          _Panel(
            title: 'Update policy',
            subtitle: 'Policy is about intent. The signature check is about '
                'possibility, and it runs regardless — a major is refused '
                'under every policy, including a range.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                RadioGroup<LocalazeUpdatePolicy>(
                  groupValue: widget.policy,
                  onChanged: (value) =>
                      value == null ? null : widget.onPolicy(value),
                  child: Column(
                    children: <Widget>[
                      for (final option in <(String, LocalazeUpdatePolicy)>[
                        ('none — never fetch', LocalazeUpdatePolicy.none),
                        (
                          'patchOnly — wording fixes',
                          LocalazeUpdatePolicy.patchOnly
                        ),
                        (
                          'minorAndPatch — the default',
                          LocalazeUpdatePolicy.minorAndPatch
                        ),
                      ])
                        RadioListTile<LocalazeUpdatePolicy>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(option.$1),
                          value: option.$2,
                        ),
                    ],
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('applyImmediately'),
                  subtitle: const Text(
                      'Off by default: text changing under a user mid-session '
                      'is worse than being one launch out of date.'),
                  value: widget.applyImmediately,
                  onChanged: widget.onApplyImmediately,
                ),
              ],
            ),
          ),
          _Panel(
            title: 'Update',
            subtitle: 'Never throws, and never blocks a screen.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: busy ? null : () => _update(controller),
                      icon: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_download_outlined),
                      label: const Text('Check for update'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        final applied = controller.applyPending();
                        _snack(applied
                            ? 'Applied the held-back catalog'
                            : 'Nothing pending');
                      },
                      child: const Text('Apply pending'),
                    ),
                  ],
                ),
                if (lastStatus != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _StatusCard(status: lastStatus!),
                ],
              ],
            ),
          ),
          _Panel(
            title: 'Diagnostics',
            subtitle: 'Nothing in the SDK throws, so a wrong key and a quiet '
                'network look identical from outside. This callback is how '
                'anyone finds out an integration never worked.',
            trailing: TextButton(
              onPressed: widget.onClearDiagnostics,
              child: const Text('Clear'),
            ),
            child: widget.diagnostics.isEmpty
                ? Text(
                    'Nothing reported.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final message in widget.diagnostics.take(12))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '• $message',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                    ],
                  ),
          ),
          _Panel(
            title: 'Notes',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'This app configures no cache directory, so an applied '
                  'update lasts for the session only. That is the documented '
                  'default, not a failure: the SDK has no dependency that can '
                  'find a writable directory, and adding one would push it '
                  'onto every consuming app.\n\n'
                  'Server: $baseUrl',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _update(LocalazeController<Localaze> controller) async {
    setState(() => busy = true);
    final status = await controller.update();
    if (!mounted) return;
    setState(() {
      busy = false;
      lastStatus = status;
    });
  }

  /// Switches what the stub server offers, through its control endpoint.
  ///
  /// The real read API has no such thing — this is the demo harness, not the
  /// SDK, which is why it uses a plain http call rather than anything from the
  /// package.
  Future<void> _serve(String name) async {
    try {
      await http.get(Uri.parse('$baseUrl/control/serve/$name'));
      if (!mounted) return;
      setState(() => scenario = name);
    } catch (error) {
      _snack('Could not reach the stub server at $baseUrl');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Mirrors the scenarios in `../../contract/stub-server/serve.dart`.
const Map<String, String> _scenarios = <String, String>{
  'base': '1.0.0 — what the app was built against. Nothing to take.',
  'patch': '1.0.1 — a wording fix. Accepted under patchOnly and above.',
  'minor': '1.1.0 — adds a key. Refused under patchOnly.',
  'retyped': '1.0.2 — a patch that retypes count from NUMBER to STRING. '
      'Policy accepts it, every key is present, and the parameter is still '
      'called "count". Only the type check refuses it.',
  'major': '2.0.0 — drops a key. Refused under every policy.',
  'malformed': '1.0.4 — a body with no messages.',
  'down': 'Every request fails, for the offline path.',
};

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final LocalazeFetchStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (Color colour, IconData icon, String headline) =
        switch (status.outcome) {
      LocalazeFetchOutcome.applied => (
          scheme.primary,
          Icons.check_circle_outline,
          'Applied'
        ),
      LocalazeFetchOutcome.upToDate => (
          scheme.outline,
          Icons.done_all,
          'Already up to date'
        ),
      LocalazeFetchOutcome.refusedByPolicy => (
          scheme.tertiary,
          Icons.block,
          'Refused by policy'
        ),
      LocalazeFetchOutcome.refusedBySignature => (
          scheme.error,
          Icons.gpp_bad_outlined,
          'Refused by signature'
        ),
      LocalazeFetchOutcome.failed => (
          scheme.error,
          Icons.cloud_off_outlined,
          'Failed'
        ),
      LocalazeFetchOutcome.none => (scheme.outline, Icons.circle_outlined, '—'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colour.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: colour),
              const SizedBox(width: 8),
              Text(headline,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: colour)),
              if (status.version != null) ...<Widget>[
                const Spacer(),
                Text(status.version!,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
          if (status.detail != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(status.detail!,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.call, this.rendered);

  final String call;
  final String rendered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 168,
            child: Text(call,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontFamily: 'monospace')),
          ),
          Expanded(
            child: Text(rendered,
                style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
