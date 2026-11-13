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
import 'host_page.dart';
import 'protocol.dart';
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

class _TiptapViewState extends State<TiptapView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  late TiptapWebViewSession _session;
  late String _token;
  TiptapReadyInfo? _ready;
  double? _height;
  bool _rendered = false;
  int _callId = 0;
  final Map<String, ({String method, Completer<Object?> completer})> _pending = {};
  bool _needsLoad = false;
  TiptapContent? _shownContent;
  TiptapTheme? _shownTheme;
  Route<void>? _fullscreen;

  static final Set<Factory<OneSequenceGestureRecognizer>> _defaultGestures = {
    Factory<OneSequenceGestureRecognizer>(HorizontalDragGestureRecognizer.new),
  };

  Uri get _baseUrl => widget.baseUrl ?? TiptapView.defaultBaseUrl;

  TiptapTheme _theme(BuildContext context) => widget.theme ?? TiptapTheme.of(context);

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _token = TiptapHostPage.newToken();
    _ready = null;
    _rendered = false;
    _shownContent = null;
    _shownTheme = null;
    _session = widget.adapter.createSession(
      channelName: TiptapProtocol.channel,
      callbacks: TiptapSessionCallbacks(
        onMessage: _onMessage,
        onNavigation: _onNavigation,
        onShowFullscreen: _showFullscreen,
        onHideFullscreen: _hideFullscreen,
      ),
    );
    // Loading reads the asset bundle from the context, which initState may not do yet.
    _needsLoad = true;
  }

  Future<void> _load() async {
    _needsLoad = false;
    try {
      final assets = await widget.bundle.load(DefaultAssetBundle.of(context));
      if (!mounted) return;
      await _session.loadHtml(
        TiptapHostPage.build(js: assets.js, css: assets.css, token: _token),
        baseUrl: _baseUrl,
      );
    } catch (error, stack) {
      _report(TiptapError('Could not load the bundle: $error', context: 'load', stack: '$stack'));
    }
  }

  @override
  void didUpdateWidget(TiptapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) updateKeepAlive();
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      if (_ready != null) widget.controller?.attach(_call);
    }
    if (oldWidget.adapter != widget.adapter || oldWidget.bundle != widget.bundle || oldWidget.baseUrl != widget.baseUrl) {
      _restart();
      return;
    }
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_needsLoad) unawaited(_load());
    // The Material theme may have changed, light to dark for one.
    _sync();
  }

  void _restart() {
    widget.controller?.detach();
    _failPending('The view was reloaded');
    _session.dispose();
    setState(_start);
    unawaited(_load());
  }

  /// Sends the theme and content when they differ from what the page shows.
  void _sync() {
    if (_ready == null) return;
    final theme = _theme(context);
    if (theme != _shownTheme) {
      _shownTheme = theme;
      unawaited(_send('setTheme', theme.toCssVariables()));
    }
    if (widget.content != _shownContent) {
      _shownContent = widget.content;
      unawaited(_send('setContent', widget.content.toParams()).then((_) {
        if (mounted && !_rendered) setState(() => _rendered = true);
      }));
    }
  }

  // Bridge -------------------------------------------------------------------------------------------

  Future<Object?> _call(String method, Map<String, Object?> params) {
    final id = '${++_callId}';
    final completer = Completer<Object?>();
    _pending[id] = (method: method, completer: completer);
    unawaited(_session.runJavaScript(TiptapProtocol.call(id, method, params)).catchError((Object error) {
      _pending.remove(id)?.completer.completeError(TiptapCallException(method, '$error'));
    }));
    return completer.future;
  }

  Future<void> _send(String method, Map<String, Object?> params) async {
    try {
      await _call(method, params);
    } on TiptapCallException catch (error) {
      _report(TiptapError(error.message, context: method));
    }
  }

  void _onMessage(String text) {
    final message = TiptapProtocol.parse(text, token: _token);
    switch (message) {
      case null:
        return;
      case TiptapResponseMessage(:final id, :final result, :final error):
        final call = _pending.remove(id);
        if (call == null) return;
        if (error != null) {
          call.completer.completeError(TiptapCallException(call.method, error));
        } else {
          call.completer.complete(result);
        }
      case TiptapEventMessage(:final event, :final payload):
        _onEvent(event, payload);
    }
  }

  void _onEvent(String name, Map<String, Object?> payload) {
    if (!mounted) return;
    widget.onEvent?.call(TiptapEvent(name, payload));
    switch (name) {
      case 'ready':
        _onReady(TiptapReadyInfo.fromPayload(payload));
      case 'height':
        final height = (payload['height'] as num?)?.toDouble();
        if (height != null && height != _height) setState(() => _height = height);
      case 'linkTap':
        widget.onLinkTap?.call(TiptapLinkTap.fromPayload(payload, baseUri: _baseUrl));
      case 'imageTap':
        final box = context.findRenderObject();
        final origin = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) : null;
        widget.onImageTap?.call(TiptapImageTap.fromPayload(payload, viewOrigin: origin));
      case 'error':
        _report(TiptapError.fromPayload(payload));
      default:
        for (final extension in widget.extensions) {
          extension.events[name]?.call(payload);
        }
    }
  }

  void _onReady(TiptapReadyInfo info) {
    if (info.protocol != TiptapProtocol.version) {
      _report(TiptapError(
        'The bundle speaks protocol ${info.protocol}, this package speaks ${TiptapProtocol.version}. '
        'Rebuild the bundle with this version of tiptap_view.',
        context: 'protocol',
      ));
      return;
    }
    _ready = info;
    final missing = [
      for (final extension in widget.extensions)
        if (!info.extensions.contains(extension.name)) extension.name,
    ];
    if (missing.isNotEmpty) {
      _report(TiptapError('The bundle "${info.bundle}" lacks extensions: ${missing.join(', ')}', context: 'extensions'));
    }
    widget.controller?.attach(_call);
    widget.onReady?.call(info);
    _sync();
  }

  FutureOr<bool> _onNavigation(TiptapNavigation navigation) {
    // Embedded players load their own pages in frames.
    if (!navigation.isMainFrame) return true;
    // Anything else would replace the page with the bridge. A link the runtime did not catch ends up here.
    widget.onEvent?.call(TiptapEvent('navigationBlocked', {'url': navigation.url.toString()}));
    // The page itself, reloading or jumping to an anchor, is not a link the reader tapped.
    if (navigation.url.removeFragment() == _baseUrl.removeFragment()) return false;
    widget.onLinkTap?.call(TiptapLinkTap(
      href: navigation.url.toString(),
      text: '',
      attributes: const {},
      uri: navigation.url,
    ));
    return false;
  }

  void _report(TiptapError error) {
    if (widget.onError != null) {
      widget.onError!(error);
    } else {
      debugPrint('$error');
    }
  }

  void _failPending(String reason) {
    for (final call in _pending.values) {
      call.completer.completeError(TiptapCallException(call.method, reason));
    }
    _pending.clear();
  }

  // Fullscreen video (Android hands the player over as a widget) ------------------------------------

  void _showFullscreen(Widget player, VoidCallback onHidden) {
    final route = PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (context, _, _) => ColoredBox(color: Colors.black, child: player),
    );
    _fullscreen = route;
    unawaited(Navigator.of(context, rootNavigator: true).push(route).then((_) {
      if (_fullscreen == route) {
        _fullscreen = null;
        onHidden();
      }
    }));
  }

  void _hideFullscreen() {
    final route = _fullscreen;
    _fullscreen = null;
    if (route != null && route.isActive) Navigator.of(context, rootNavigator: true).removeRoute(route);
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _failPending('The view was disposed');
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final height = math.max(_height ?? widget.minHeight, widget.minHeight);
    final loading = widget.loadingBuilder;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _session.build(context, gestureRecognizers: widget.gestureRecognizers ?? _defaultGestures),
          if (!_rendered && loading != null) Positioned.fill(child: loading(context)),
        ],
      ),
    );
  }
}
