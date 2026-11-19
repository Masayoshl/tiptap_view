import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'adapter.dart';
import 'bundle.dart';
import 'controller.dart';
import 'events.dart';
import 'extension.dart';
import 'host_page.dart';
import 'protocol.dart';
import 'theme.dart';

/// What `TiptapView` and `TiptapEditor` share: the page with the runtime in a WebView, and the bridge to it.
///
/// The state of either widget mixes this in and says which [pageMode] it starts the runtime in. The mixin
/// loads the bundle into the host page, checks the runtime's `ready` (protocol, mode, extensions), calls
/// runtime methods, answers its requests, keeps the theme and the height in sync and shows fullscreen
/// video. The widget handles the rest of the runtime's events and its own content.
mixin TiptapPageHost<T extends StatefulWidget> on State<T> {
  // What the widget provides. -------------------------------------------------------------------------

  /// The runtime mode the page starts in: `view` or `editor`.
  String get pageMode;
  TiptapWebViewAdapter get pageAdapter;
  TiptapBundle get pageBundle;
  Uri get pageBaseUrl;
  TiptapTheme pageTheme(BuildContext context);
  List<TiptapExtension> get pageExtensions;
  ValueChanged<TiptapEvent>? get pageOnEvent;
  ValueChanged<TiptapError>? get pageOnError;

  /// The runtime is ready and speaks this package's protocol and mode.
  void pageReady(TiptapReadyInfo info);

  /// An event the mixin does not handle itself. Return true when the widget handled it; otherwise the
  /// event goes to the handlers of [pageExtensions].
  bool pageEvent(String name, Map<String, Object?> payload) => false;

  /// The widget's own answer to the runtime's request [name], before the extensions' handlers.
  TiptapRequestHandler? pageRequestHandler(String name) => null;

  /// The main frame wants to go to [url]; it never may, since that would replace the page with the bridge.
  /// The page itself (a reload, an anchor) is filtered out before this is called.
  void pageNavigationBlocked(Uri url) {}

  /// The page was replaced (a new adapter, bundle or base URL) or the widget is going away: calls to the old
  /// page have failed, and a new `ready` will follow for a new page.
  void pageDetached() {}

  // State. --------------------------------------------------------------------------------------------

  late TiptapWebViewSession _session;
  late String _token;
  TiptapReadyInfo? _ready;
  double? _height;
  int _callId = 0;
  final Map<String, ({String method, Completer<Object?> completer})> _pending = {};
  bool _needsLoad = false;
  TiptapTheme? _shownTheme;
  Route<void>? _fullscreen;

  /// The runtime's `ready`, once it has come and passed the checks; null before and after a restart.
  TiptapReadyInfo? get pageReadyInfo => _ready;

  /// The height of the page's content, once the runtime has measured it.
  double? get pageHeight => _height;

  static final Set<Factory<OneSequenceGestureRecognizer>> defaultGestures = {
    Factory<OneSequenceGestureRecognizer>(HorizontalDragGestureRecognizer.new),
  };

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _token = TiptapHostPage.newToken();
    _ready = null;
    _shownTheme = null;
    _session = pageAdapter.createSession(
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
      final assets = await pageBundle.load(DefaultAssetBundle.of(context));
      if (!mounted) return;
      await _session.loadHtml(
        TiptapHostPage.build(js: assets.js, css: assets.css, token: _token, mode: pageMode),
        baseUrl: pageBaseUrl,
      );
    } catch (error, stack) {
      reportPageError(TiptapError('Could not load the bundle: $error', context: 'load', stack: '$stack'));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_needsLoad) unawaited(_load());
    // The Material theme may have changed, light to dark for one.
    syncPageTheme();
  }

  /// Loads a fresh page: for a new adapter, bundle or base URL.
  void restartPage() {
    pageDetached();
    _failPending('The view was reloaded');
    _session.dispose();
    setState(_start);
    unawaited(_load());
  }

  /// Sends the theme when it differs from what the page shows.
  void syncPageTheme() {
    if (_ready == null) return;
    final theme = pageTheme(context);
    if (theme == _shownTheme) return;
    _shownTheme = theme;
    unawaited(sendToPage('setTheme', theme.toCssVariables()));
  }

  // Bridge -------------------------------------------------------------------------------------------

  /// Calls [method] in the runtime. Fails with a [TiptapCallException] when the runtime answers with an error
  /// or the page goes away first.
  Future<Object?> callPage(String method, Map<String, Object?> params) {
    final id = '${++_callId}';
    final completer = Completer<Object?>();
    _pending[id] = (method: method, completer: completer);
    unawaited(_session.runJavaScript(TiptapProtocol.call(id, method, params)).catchError((Object error) {
      _pending.remove(id)?.completer.completeError(TiptapCallException(method, '$error'));
    }));
    return completer.future;
  }

  /// [callPage] for calls nobody waits on: a failure becomes an error report.
  Future<Object?> sendToPage(String method, Map<String, Object?> params) async {
    try {
      return await callPage(method, params);
    } on TiptapCallException catch (error) {
      reportPageError(TiptapError(error.message, context: method));
      return null;
    }
  }

  void reportPageError(TiptapError error) {
    final onError = pageOnError;
    if (onError != null) {
      onError(error);
    } else {
      debugPrint('$error');
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
      case TiptapRequestMessage(:final id, :final name, :final payload):
        unawaited(_onRequest(id, name, payload));
    }
  }

  void _onEvent(String name, Map<String, Object?> payload) {
    if (!mounted) return;
    pageOnEvent?.call(TiptapEvent(name, payload));
    switch (name) {
      case 'ready':
        _onReady(TiptapReadyInfo.fromPayload(payload));
      case 'height':
        final height = (payload['height'] as num?)?.toDouble();
        if (height != null && height != _height) setState(() => _height = height);
      case 'error':
        reportPageError(TiptapError.fromPayload(payload));
      default:
        if (pageEvent(name, payload)) return;
        for (final extension in pageExtensions) {
          extension.events[name]?.call(payload);
        }
    }
  }

  void _onReady(TiptapReadyInfo info) {
    if (info.protocol != TiptapProtocol.version) {
      reportPageError(TiptapError(
        'The bundle speaks protocol ${info.protocol}, this package speaks ${TiptapProtocol.version}. '
        'Rebuild the bundle with this version of tiptap_view.',
        context: 'protocol',
      ));
      return;
    }
    if (info.mode != pageMode) {
      reportPageError(TiptapError(
        '$T needs a bundle with the "$pageMode" runtime mode; the bundle "${info.bundle}" has '
        '${info.modes.isEmpty ? 'none' : info.modes.join(', ')}. Rebuild it with this version of tiptap_view.',
        context: 'mode',
      ));
      return;
    }
    _ready = info;
    final missing = [
      for (final extension in pageExtensions)
        if (!info.extensions.contains(extension.name)) extension.name,
    ];
    if (missing.isNotEmpty) {
      reportPageError(TiptapError('The bundle "${info.bundle}" lacks extensions: ${missing.join(', ')}', context: 'extensions'));
    }
    syncPageTheme();
    pageReady(info);
  }

  Future<void> _onRequest(String id, String name, Map<String, Object?> payload) async {
    final session = _session;
    TiptapRequestHandler? handler = pageRequestHandler(name);
    for (final extension in handler == null ? pageExtensions : const <TiptapExtension>[]) {
      handler = extension.requests[name];
      if (handler != null) break;
    }
    String script;
    if (handler == null) {
      script = TiptapProtocol.respond(id, error: 'No handler for request: $name');
    } else {
      try {
        script = TiptapProtocol.respond(id, result: await handler(payload));
      } catch (error) {
        script = TiptapProtocol.respond(id, error: '$error');
      }
    }
    // The page may have been replaced or disposed while the handler ran; its request died with it.
    if (!mounted || session != _session) return;
    try {
      await session.runJavaScript(script);
    } catch (error) {
      reportPageError(TiptapError('Could not answer the request $name: $error', context: 'request'));
    }
  }

  FutureOr<bool> _onNavigation(TiptapNavigation navigation) {
    // Embedded players load their own pages in frames.
    if (!navigation.isMainFrame) return true;
    // Anything else would replace the page with the bridge.
    pageOnEvent?.call(TiptapEvent('navigationBlocked', {'url': navigation.url.toString()}));
    // The page itself, reloading or jumping to an anchor, is not a link the reader tapped.
    if (navigation.url.removeFragment() != pageBaseUrl.removeFragment()) pageNavigationBlocked(navigation.url);
    return false;
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
    pageDetached();
    _failPending('The view was disposed');
    _session.dispose();
    super.dispose();
  }

  /// The WebView, sized by the widget around it.
  Widget buildPage(BuildContext context, {Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers}) =>
      _session.build(context, gestureRecognizers: gestureRecognizers ?? defaultGestures);
}
