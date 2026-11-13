import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiptap_view/tiptap_view.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tiptap_view',
      themeMode: _mode,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
      home: SandboxPage(
        dark: _mode == ThemeMode.dark,
        onToggleDark: () => setState(() => _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
      ),
    );
  }
}

/// A document the sandbox can show.
enum Fixture {
  article('Article', 'assets/fixtures/article.html'),
  legacy('Old editor', 'assets/fixtures/legacy.html'),
  custom('Custom JSON', 'assets/fixtures/custom.json'),
  long('Long', 'assets/fixtures/article.html'),
  unknown('Unknown node', 'assets/fixtures/unknown.json');

  const Fixture(this.label, this.asset);

  final String label;
  final String asset;

  bool get isJson => asset.endsWith('.json');
}

/// The example app's own bundle, with the Details and Callout extensions (see tiptap/entry.js).
final TiptapBundle exampleBundle = TiptapBundle.asset('assets/tiptap');

class SandboxPage extends StatefulWidget {
  const SandboxPage({super.key, required this.dark, required this.onToggleDark});

  final bool dark;
  final VoidCallback onToggleDark;

  @override
  State<SandboxPage> createState() => _SandboxPageState();
}

class _SandboxPageState extends State<SandboxPage> {
  final _controller = TiptapViewController();
  final List<String> _log = [];
  Fixture _fixture = Fixture.article;
  bool _customBundle = true;
  bool _viaJson = false;
  bool _showLog = true;
  TiptapContent? _content;

  @override
  void initState() {
    super.initState();
    _loadFixture();
  }

  Future<void> _loadFixture() async {
    final text = await rootBundle.loadString(_fixture.asset);
    TiptapContent content;
    if (_fixture.isJson) {
      content = TiptapContent.json(Map<String, Object?>.from(jsonDecode(text) as Map));
    } else {
      final html = _fixture == Fixture.long ? List.filled(30, text).join('<hr>') : text;
      content = TiptapContent.html(html);
      if (_viaJson) {
        // HTML → JSON with the bundle's schema, then shown from JSON: what the schema keeps.
        final json = await _controller.htmlToJson(html);
        _write('htmlToJson: ${jsonEncode(json).length} chars of JSON');
        content = TiptapContent.json(json);
      }
    }
    if (mounted) setState(() => _content = content);
  }

  void _write(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, '${TimeOfDay.now().format(context)}  $line');
      if (_log.length > 60) _log.removeLast();
    });
  }

  void _select(Fixture fixture) {
    setState(() => _fixture = fixture);
    _loadFixture();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = _content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('tiptap_view'),
        actions: [
          IconButton(
            tooltip: 'Dark theme',
            icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleDark,
          ),
          IconButton(
            tooltip: 'Event log',
            icon: Icon(_showLog ? Icons.terminal : Icons.terminal_outlined),
            onPressed: () => setState(() => _showLog = !_showLog),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final fixture in Fixture.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('fixture-${fixture.name}'),
                      label: Text(fixture.label),
                      selected: fixture == _fixture,
                      onSelected: (_) => _select(fixture),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  key: const Key('custom-bundle'),
                  label: const Text('Example bundle'),
                  selected: _customBundle,
                  onSelected: (value) => setState(() => _customBundle = value),
                ),
                FilterChip(
                  key: const Key('via-json'),
                  label: const Text('HTML via JSON'),
                  selected: _viaJson,
                  onSelected: _fixture.isJson
                      ? null
                      : (value) {
                          setState(() => _viaJson = value);
                          _loadFixture();
                        },
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: ListView(
              key: const Key('page'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'A Flutter header. The page scrolls; the view below grows to its content.',
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (content != null)
                  TiptapView(
                    key: const Key('tiptap-view'),
                    content: content,
                    controller: _controller,
                    bundle: _customBundle ? exampleBundle : TiptapBundle.defaults,
                    baseUrl: Uri.parse('https://docs.example.com/'),
                    extensions: [
                      if (_customBundle)
                        TiptapExtension('callout', events: {
                          'calloutTap': (payload) => _write('calloutTap: ${payload['tone']} — ${payload['text']}'),
                        }),
                    ],
                    loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
                    minHeight: 120,
                    onReady: (info) => _write('ready: ${info.bundle} runtime ${info.runtimeVersion}, '
                        'tiptap ${info.tiptapVersion}, ${info.extensions.length} extensions'),
                    onLinkTap: (link) {
                      final internal = link.isInternal(Uri.parse('https://docs.example.com/'));
                      _write('link: ${link.href} ${internal ? '(internal)' : '(external)'} ${link.attributes}');
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(content: Text('${internal ? 'Open in app' : 'Open in browser'}: ${link.href}')));
                    },
                    onImageTap: (image) => _write('image: ${image.src}'),
                    onError: (error) => _write('ERROR $error'),
                    onEvent: (event) {
                      if (event.name != 'ready' && event.name != 'linkTap' && event.name != 'imageTap' && event.name != 'error') {
                        _write('${event.name}: ${event.payload}');
                      }
                    },
                  ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('A Flutter footer, right after the document.', key: const Key('footer'), style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                ),
              ],
            ),
          ),
          if (_showLog)
            Container(
              height: 150,
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              child: ListView(
                key: const Key('event-log'),
                padding: const EdgeInsets.all(8),
                children: [
                  for (final line in _log)
                    Text(line, style: const TextStyle(fontFamily: 'Menlo', fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
