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
import 'webview_flutter_adapter.dart';

/// Shows a TipTap document, read-only, in a WebView that grows to the height of its content.
///
/// Put it in a scrollable page like any other widget: the page scrolls, the view does not. Links do not
/// navigate by themselves; [onLinkTap] decides what they do.
class TiptapView extends StatefulWidget {
  const TiptapView({
    super.key,
    required this.content,
    this.bundle = TiptapBundle.defaults,
    this.theme,
    this.controller,
    this.adapter = const WebViewFlutterAdapter(),
    this.extensions = const [],
    this.baseUrl,
    this.onReady,
    this.onLinkTap,
    this.onImageTap,
    this.onEvent,
    this.onError,
    this.loadingBuilder,
    this.minHeight = 1,
    this.gestureRecognizers,
    this.keepAlive = true,
  });

  /// Keeps the view, and its loaded page, alive when a lazy list (ListView, CustomScrollView) scrolls it out
  /// of view. Without it the list disposes the WebView and the page loads again on the way back.
  final bool keepAlive;

  final TiptapContent content;
  final TiptapBundle bundle;

  /// How the document looks; [TiptapTheme.of] the context when null.
  final TiptapTheme? theme;
  final TiptapViewController? controller;
  final TiptapWebViewAdapter adapter;

  /// The extensions the app relies on. When the bundle lacks one, [onError] says so once it is ready.
  final List<TiptapExtension> extensions;

  /// The page's address: relative links and images resolve against it, and embeds see its origin as the
  /// referrer. Defaults to [defaultBaseUrl].
  final Uri? baseUrl;

  final ValueChanged<TiptapReadyInfo>? onReady;
  final ValueChanged<TiptapLinkTap>? onLinkTap;
  final ValueChanged<TiptapImageTap>? onImageTap;

  /// Every event from the runtime, the ones with their own callbacks too.
  final ValueChanged<TiptapEvent>? onEvent;
  final ValueChanged<TiptapError>? onError;

  /// Shown over the view until the first content has been laid out.
  final WidgetBuilder? loadingBuilder;

  /// The height while nothing has been measured yet.
  final double minHeight;

  /// Gestures the WebView takes from the page around it. By default, horizontal drags, so wide tables and
  /// code blocks scroll sideways while vertical scrolling stays with the page.
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  static final Uri defaultBaseUrl = Uri.parse('https://tiptap-view.local/');

  @override
  State<TiptapView> createState() => _TiptapViewState();
}

class _TiptapViewState extends State<TiptapView> with TiptapPageHost<TiptapView>, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  bool _rendered = false;
  TiptapContent? _shownContent;

  @override
  String get pageMode => 'view';
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
    _rendered = false;
    _shownContent = null;
  }

  @override
  bool pageEvent(String name, Map<String, Object?> payload) {
    switch (name) {
      case 'linkTap':
        widget.onLinkTap?.call(TiptapLinkTap.fromPayload(payload, baseUri: pageBaseUrl));
        return true;
      case 'imageTap':
        final box = context.findRenderObject();
        final origin = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) : null;
        widget.onImageTap?.call(TiptapImageTap.fromPayload(payload, viewOrigin: origin));
        return true;
    }
    return false;
  }

  @override
  void pageNavigationBlocked(Uri url) {
    // A link the runtime did not catch ends up here.
    widget.onLinkTap?.call(TiptapLinkTap(href: url.toString(), text: '', attributes: const {}, uri: url));
  }

  @override
  void didUpdateWidget(TiptapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) updateKeepAlive();
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      if (pageReadyInfo != null) widget.controller?.attach(callPage);
    }
    if (oldWidget.adapter != widget.adapter || oldWidget.bundle != widget.bundle || oldWidget.baseUrl != widget.baseUrl) {
      restartPage();
      return;
    }
    syncPageTheme();
    _syncContent();
  }

  /// Sends the content when it differs from what the page shows.
  void _syncContent() {
    if (pageReadyInfo == null || widget.content == _shownContent) return;
    _shownContent = widget.content;
    unawaited(sendToPage('setContent', widget.content.toParams()).then((_) {
      if (mounted && !_rendered) setState(() => _rendered = true);
    }));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final height = math.max(pageHeight ?? widget.minHeight, widget.minHeight);
    final loading = widget.loadingBuilder;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          buildPage(context, gestureRecognizers: widget.gestureRecognizers),
          // Until the content is in and measured: before its first height the view is still at minHeight,
          // showing a slice of the page.
          if ((!_rendered || pageHeight == null) && loading != null) Positioned.fill(child: loading(context)),
        ],
      ),
    );
  }
}
