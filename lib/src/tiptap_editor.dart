import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'adapter.dart';
import 'bundle.dart';
import 'content.dart';
import 'controller.dart';
import 'events.dart';
import 'extension.dart';
import 'page_host.dart';
import 'theme.dart';
import 'tiptap_view.dart';
import 'webview_flutter_adapter.dart';

/// Edits a TipTap document in a WebView, with the bundle's schema and extensions: the same bundle as
/// [TiptapView]'s, started in its editor mode.
///
/// [content] is the document to open. Every new value (by `==`) opens that document afresh: edits so far,
/// and their undo history, are gone. Read the edited document with [TiptapEditorController.getContent];
/// [onChange] says when there is something new to read.
///
/// JSON is opened only when the bundle's schema can hold all of it (see [TiptapIncompatibleContent]).
/// HTML is converted through the schema, as the web editor does on a first edit.
class TiptapEditor extends StatefulWidget {
  const TiptapEditor({
    super.key,
    required this.content,
    this.editable = true,
    this.bundle = TiptapBundle.defaults,
    this.theme,
    this.controller,
    this.adapter = const WebViewFlutterAdapter(),
    this.extensions = const [],
    this.baseUrl,
    this.onReady,
    this.onOpened,
    this.onChange,
    this.onIncompatibleContent,
    this.onEvent,
    this.onError,
    this.loadingBuilder,
    this.minHeight = 1,
    this.gestureRecognizers,
  });

  final TiptapContent content;

  /// Whether the document can be edited; false shows it read-only, with the editor's own rendering.
  final bool editable;

  final TiptapBundle bundle;

  /// How the document looks; [TiptapTheme.of] the context when null.
  final TiptapTheme? theme;
  final TiptapEditorController? controller;
  final TiptapWebViewAdapter adapter;

  /// The extensions the app relies on: missing ones are reported, their events and requests routed.
  final List<TiptapExtension> extensions;

  /// The page's address: relative links and images resolve against it. Defaults to
  /// [TiptapView.defaultBaseUrl].
  final Uri? baseUrl;

  final ValueChanged<TiptapReadyInfo>? onReady;

  /// [content] is open for editing.
  final VoidCallback? onOpened;
  final ValueChanged<TiptapEditorChange>? onChange;

  /// [content] could not be opened for editing. Without this callback it is reported to [onError].
  final ValueChanged<TiptapIncompatibleContent>? onIncompatibleContent;

  /// Every event from the runtime, the ones with their own callbacks too.
  final ValueChanged<TiptapEvent>? onEvent;
  final ValueChanged<TiptapError>? onError;

  /// Shown over the editor until the first document is open.
  final WidgetBuilder? loadingBuilder;

  /// The height while nothing has been measured yet.
  final double minHeight;

  /// Gestures the WebView takes from the page around it; by default, horizontal drags.
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  @override
  State<TiptapEditor> createState() => _TiptapEditorState();
}

class _TiptapEditorState extends State<TiptapEditor> with TiptapPageHost<TiptapEditor> {
  bool _opened = false;
  TiptapContent? _shownContent;

  @override
  String get pageMode => 'editor';
  @override
  TiptapWebViewAdapter get pageAdapter => widget.adapter;
  @override
  TiptapBundle get pageBundle => widget.bundle;
  @override
  Uri get pageBaseUrl => widget.baseUrl ?? TiptapView.defaultBaseUrl;
  @override
  TiptapTheme pageTheme(BuildContext context) => widget.theme ?? TiptapTheme.of(context);
  @override
  List<TiptapExtension> get pageExtensions => widget.extensions;
  @override
  ValueChanged<TiptapEvent>? get pageOnEvent => widget.onEvent;
  @override
  ValueChanged<TiptapError>? get pageOnError => widget.onError;

  @override
  void pageReady(TiptapReadyInfo info) {
    widget.controller?.attach(callPage);
    widget.onReady?.call(info);
    _syncContent();
  }

  @override
  void pageDetached() {
    widget.controller?.detach();
    _opened = false;
    _shownContent = null;
  }

  @override
  bool pageEvent(String name, Map<String, Object?> payload) {
    if (name != 'change') return false;
    widget.onChange?.call(TiptapEditorChange((payload['version'] as num?)?.toInt() ?? 0));
    return true;
  }

  @override
  void didUpdateWidget(TiptapEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      if (pageReadyInfo != null) widget.controller?.attach(callPage);
    }
    if (oldWidget.adapter != widget.adapter || oldWidget.bundle != widget.bundle || oldWidget.baseUrl != widget.baseUrl) {
      restartPage();
      return;
    }
    syncPageTheme();
    if (widget.content != _shownContent) {
      _syncContent();
    } else if (oldWidget.editable != widget.editable && _opened) {
      unawaited(sendToPage('setEditable', {'editable': widget.editable}));
    }
  }

  /// Opens [TiptapEditor.content] when it differs from the open document.
  void _syncContent() {
    if (pageReadyInfo == null || widget.content == _shownContent) return;
    final content = _shownContent = widget.content;
    unawaited(sendToPage('setContent', {...content.toParams(), 'editable': widget.editable}).then((result) {
      // A newer document may have been sent meanwhile, or the page replaced.
      if (!mounted || content != _shownContent || result is! Map) return;
      if (result['status'] == 'incompatible') {
        final incompatible = TiptapIncompatibleContent.fromPayload(Map<String, Object?>.from(result));
        final onIncompatible = widget.onIncompatibleContent;
        if (onIncompatible != null) {
          onIncompatible(incompatible);
        } else {
          reportPageError(TiptapError('The document cannot be edited with this bundle: $incompatible', context: 'content'));
        }
      } else {
        widget.onOpened?.call();
      }
      if (!_opened) setState(() => _opened = true);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final height = math.max(pageHeight ?? widget.minHeight, widget.minHeight);
    final loading = widget.loadingBuilder;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          buildPage(context, gestureRecognizers: widget.gestureRecognizers),
          if (!_opened && loading != null) Positioned.fill(child: loading(context)),
        ],
      ),
    );
  }
}
