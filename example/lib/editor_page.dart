import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tiptap_view/tiptap_view.dart';

/// The sandbox's editor: the same bundle as the view, a Flutter toolbar on the controller's state, fake
/// uploads, links and embeds, and Save, which opens the saved JSON in a TiptapView.
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.bundle, required this.content});

  final TiptapBundle bundle;
  final TiptapContent content;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _controller = TiptapEditorController();
  final List<String> _log = [];
  int _version = 0;
  int _uploads = 0;
  bool _failNextUpload = false;
  TiptapIncompatibleContent? _refused;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _write(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 40) _log.removeLast();
    });
  }

  /// Stands in for the app's upload: a second and a half, then an image URL, or a failure when asked for.
  Future<TiptapUploadedImage> _fakeUpload() async {
    final fail = _failNextUpload;
    if (fail) setState(() => _failNextUpload = false);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (fail) throw Exception('The server said no');
    return TiptapUploadedImage('https://picsum.photos/seed/upload${++_uploads}/600/300');
  }

  Future<void> _insertImage() async {
    final inserted = await _controller.uploadImage(_fakeUpload);
    _write('upload: ${inserted ? 'inserted' : 'removed'}');
  }

  Future<String?> _ask(String title, {String initial = '', String hint = ''}) {
    final field = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: field, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _editLink() async {
    final link = await _controller.getLink();
    if (!mounted) return;
    final href = await _ask(link.active ? 'Edit link' : 'Add link', initial: link.href ?? '', hint: 'https://…');
    if (href == null) return;
    final done = href.isEmpty ? await _controller.removeLink() : await _controller.setLink(href, text: link.selectionEmpty && !link.active ? href : null);
    _write('link: $done');
  }

  Future<void> _insertEmbed() async {
    final url = await _ask('Embed', hint: 'A YouTube link');
    if (url == null || url.isEmpty) return;
    final type = await _controller.insertEmbed(url);
    _write(type == null ? 'embed: no resolver for $url' : 'embed: $type');
  }

  Future<void> _save() async {
    final TiptapEditorContent content;
    try {
      content = await _controller.getContent();
    } on TiptapCallException catch (error) {
      _write('save: $error');
      return;
    }
    if (!mounted) return;
    if (!content.canSave) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Not yet: ${content.errors}')));
      return;
    }
    _write('saved: version ${content.version}, ${jsonEncode(content.json).length} chars of JSON, ${content.html.length} of HTML');
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Saved, in TiptapView')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [TiptapView(bundle: widget.bundle, content: TiptapContent.json(content.json), minHeight: 120)],
        ),
      ),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final refused = _refused;
    return Scaffold(
      appBar: AppBar(
        title: Text('Editor · v$_version'),
        actions: [
          IconButton(
            key: const Key('fail-next'),
            tooltip: 'Fail the next upload',
            icon: Icon(_failNextUpload ? Icons.cloud_off : Icons.cloud_outlined),
            onPressed: () => setState(() => _failNextUpload = !_failNextUpload),
          ),
          TextButton(key: const Key('save'), onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<TiptapEditorState?>(
            valueListenable: _controller.state,
            builder: (context, state, _) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _ToolButton(icon: Icons.format_bold, label: 'Bold', active: state?.isActive('bold') ?? false, onPressed: state == null ? null : () => _controller.command('toggleBold')),
                  _ToolButton(icon: Icons.format_italic, label: 'Italic', active: state?.isActive('italic') ?? false, onPressed: state == null ? null : () => _controller.command('toggleItalic')),
                  _ToolButton(icon: Icons.title, label: 'Heading', active: state?.isActive('heading', {'level': 2}) ?? false, onPressed: state == null ? null : () => _controller.command('toggleHeading', {'level': 2})),
                  _ToolButton(icon: Icons.format_list_bulleted, label: 'List', active: state?.isActive('bulletList') ?? false, onPressed: state == null ? null : () => _controller.command('toggleBulletList')),
                  _ToolButton(icon: Icons.link, label: 'Link', active: state?.isActive('link') ?? false, onPressed: state == null ? null : _editLink),
                  _ToolButton(icon: Icons.image_outlined, label: 'Image', onPressed: state == null ? null : _insertImage),
                  _ToolButton(icon: Icons.smart_display_outlined, label: 'Embed', onPressed: state == null ? null : _insertEmbed),
                  _ToolButton(icon: Icons.undo, label: 'Undo', onPressed: state?.canUndo ?? false ? () => _controller.command('undo') : null),
                  _ToolButton(icon: Icons.redo, label: 'Redo', onPressed: state?.canRedo ?? false ? () => _controller.command('redo') : null),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          if (refused != null)
            MaterialBanner(
              content: Text('This document cannot be edited with this bundle: ${refused.reason.name} ${refused.types} ${refused.attributes}'),
              actions: [TextButton(onPressed: () => setState(() => _refused = null), child: const Text('OK'))],
            ),
          Expanded(
            child: ListView(
              key: const Key('editor-page'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                TiptapEditor(
                  key: const Key('tiptap-editor'),
                  bundle: widget.bundle,
                  content: widget.content,
                  controller: _controller,
                  minHeight: 240,
                  loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
                  onReady: (info) => _write('ready: ${info.bundle}, mode ${info.mode}'),
                  onOpened: () => _write('opened'),
                  onChange: (change) => setState(() => _version = change.version),
                  onIncompatibleContent: (problem) {
                    _write('refused: $problem');
                    setState(() => _refused = problem);
                  },
                  onImageUpload: (file) {
                    _write('pasted image: ${file.mimeType}, ${file.bytes.length} bytes');
                    return _fakeUpload();
                  },
                  onLinkTap: (link) => _write('link tap: ${link.href}'),
                  onError: (error) => _write('ERROR $error'),
                ),
              ],
            ),
          ),
          Container(
            height: 110,
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            child: ListView(
              key: const Key('editor-log'),
              padding: const EdgeInsets.all(8),
              children: [for (final line in _log) Text(line, style: const TextStyle(fontFamily: 'Menlo', fontSize: 11))],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onPressed, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => IconButton(
        key: Key('tool-${label.toLowerCase()}'),
        tooltip: label,
        isSelected: active,
        icon: Icon(icon),
        style: active ? IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.secondaryContainer) : null,
        onPressed: onPressed,
      );
}
