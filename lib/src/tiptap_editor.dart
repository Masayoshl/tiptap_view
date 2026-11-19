import 'dart:async';
import 'dart:convert';
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
    this.onStateChange,
    this.onIncompatibleContent,
    this.onImageUpload,
    this.onLinkTap,
    this.onEvent,
    this.onError,
    this.loadingBuilder,
    this.minHeight = 1,
    this.gestureRecognizers,
    this.keepCaretVisible = true,
    this.caretPadding = 24,
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

  /// The toolbar state changed (see [TiptapEditorState]); [TiptapEditorController.state] has it too.
  final ValueChanged<TiptapEditorState>? onStateChange;

  /// [content] could not be opened for editing. Without this callback it is reported to [onError].
  final ValueChanged<TiptapIncompatibleContent>? onIncompatibleContent;

  /// Uploads an image file pasted into the editor (a screenshot, a photo copied elsewhere). Without it, the
  /// editor does not take pasted files. Images the app picks itself go through
  /// [TiptapEditorController.uploadImage].
  final Future<TiptapUploadedImage> Function(TiptapImageFile file)? onImageUpload;

  /// A tap on a link in the document. The editor never follows links; a bubble with the link and an Edit
  /// action is the app's.
  final ValueChanged<TiptapLinkTap>? onLinkTap;

  /// Every event from the runtime, the ones with their own callbacks too.
  final ValueChanged<TiptapEvent>? onEvent;
  final ValueChanged<TiptapError>? onError;

  /// Shown over the editor until the first document is open.
  final WidgetBuilder? loadingBuilder;

  /// The height while nothing has been measured yet.
  final double minHeight;

  /// Gestures the WebView takes from the page around it; by default, horizontal drags.
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  /// Scrolls the page around the editor so the caret stays in sight: when it moves, and while the keyboard
  /// comes up. The editor grows to its content, so only the page around it can scroll; this is how it
  /// keeps the caret above the keyboard.
  final bool keepCaretVisible;

  /// Room kept above and below the caret when the page scrolls to it, in logical pixels.
  final double caretPadding;

  @override
  State<TiptapEditor> createState() => _TiptapEditorState();
}

class _TiptapEditorState extends State<TiptapEditor> with TiptapPageHost<TiptapEditor>, WidgetsBindingObserver {
  bool _opened = false;
  TiptapContent? _shownContent;

  /// The caret in the editor's own coordinates while it has focus; null without focus.
  Rect? _caret;
  bool _revealScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_pageScrolled);
    _handlesTimer?.cancel();
    super.dispose();
  }

  // Android draws selection handles in a window of their own, at a fixed place on screen; when the page
  // around the editor scrolls, they stay behind over whatever comes there. So the first scroll after a
  // pause asks the page to drop them (the selection itself stays).
  ScrollPosition? _scrollPosition;
  Timer? _handlesTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position == _scrollPosition) return;
    _scrollPosition?.removeListener(_pageScrolled);
    _scrollPosition = position?..addListener(_pageScrolled);
  }

  void _pageScrolled() {
    if (_caret == null || defaultTargetPlatform != TargetPlatform.android) return;
    final quiet = _handlesTimer == null || !_handlesTimer!.isActive;
    _handlesTimer?.cancel();
    _handlesTimer = Timer(const Duration(milliseconds: 300), () {});
    if (quiet && pageReadyInfo != null) unawaited(sendToPage('hideSelectionHandles', const {}));
  }

  double _bottomInset = 0;

  // The keyboard coming up changes the metrics every frame of its animation; the page around the editor
  // shrinks with it, and the caret has to follow. Only a growing inset counts: iOS also reports metrics
  // while the page scrolls under a focused field, and following those would pin the page to the caret.
  @override
  void didChangeMetrics() {
    final inset = View.of(context).viewInsets.bottom;
    final grew = inset > _bottomInset;
    _bottomInset = inset;
    if (grew) _revealCaret(animate: false);
  }

  void _revealCaret({bool animate = true}) {
    if (!widget.keepCaretVisible || _caret == null || _revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      final caret = _caret;
      final box = context.findRenderObject();
      if (!mounted || caret == null || box is! RenderBox || !box.attached) return;
      box.showOnScreen(
        rect: Rect.fromLTRB(caret.left, caret.top - widget.caretPadding, caret.right, caret.bottom + widget.caretPadding),
        duration: animate ? const Duration(milliseconds: 150) : Duration.zero,
        curve: Curves.easeOut,
      );
    });
    // A caret that moved inside the page changes nothing in Flutter, so no frame would come by itself.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

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
    unawaited(sendToPage('setImagePaste', {'enabled': widget.onImageUpload != null}));
    widget.onReady?.call(info);
    _syncContent();
  }

  @override
  TiptapRequestHandler? pageRequestHandler(String name) {
    final upload = widget.onImageUpload;
    if (name != 'imageUpload' || upload == null) return null;
    return (payload) async {
      final image = await upload(TiptapImageFile(
        bytes: base64Decode('${payload['data'] ?? ''}'),
        mimeType: '${payload['type'] ?? ''}',
        name: '${payload['name'] ?? ''}',
      ));
      return image.toParams();
    };
  }

  @override
  void pageDetached() {
    widget.controller?.detach();
    _caret = null;
    _opened = false;
    _shownContent = null;
  }

  @override
  bool pageEvent(String name, Map<String, Object?> payload) {
    switch (name) {
      case 'change':
        widget.onChange?.call(TiptapEditorChange((payload['version'] as num?)?.toInt() ?? 0));
        return true;
      case 'state':
        final state = TiptapEditorState.fromPayload(payload);
        widget.controller?.updateState(state);
        widget.onStateChange?.call(state);
        return true;
      case 'uploadRetry' || 'uploadCancel':
        widget.controller?.handleUploadEvent(name, payload);
        return true;
      case 'linkTap':
        widget.onLinkTap?.call(TiptapLinkTap.fromPayload(payload, baseUri: pageBaseUrl));
        return true;
      case 'caret':
        if (payload['focused'] != true) {
          _caret = null;
          return true;
        }
        double value(String key) => (payload[key] as num?)?.toDouble() ?? 0;
        _caret = Rect.fromLTRB(value('left'), value('top'), value('left') + 1, value('bottom'));
        _revealCaret();
        return true;
    }
    return false;
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
    if ((oldWidget.onImageUpload == null) != (widget.onImageUpload == null) && pageReadyInfo != null) {
      unawaited(sendToPage('setImagePaste', {'enabled': widget.onImageUpload != null}));
    }
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
