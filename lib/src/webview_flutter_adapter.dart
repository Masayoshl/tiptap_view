import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'adapter.dart';

/// [TiptapWebViewAdapter] on the official `webview_flutter` plugin (WKWebView on iOS, Android WebView).
class WebViewFlutterAdapter implements TiptapWebViewAdapter {
  const WebViewFlutterAdapter({this.inspectable = kDebugMode});

  /// Lets Safari's Web Inspector and Chrome's DevTools attach to the view. On by default in debug builds.
  final bool inspectable;

  @override
  TiptapWebViewSession createSession({required String channelName, required TiptapSessionCallbacks callbacks}) =>
      _WebViewFlutterSession(channelName: channelName, callbacks: callbacks, inspectable: inspectable);
}

class _WebViewFlutterSession implements TiptapWebViewSession {
  _WebViewFlutterSession({required String channelName, required this.callbacks, required bool inspectable}) {
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      // Videos play inside the document rather than taking over the screen, and start on the tap that
      // turned their preview into a player.
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(channelName, onMessageReceived: (message) => callbacks.onMessage(message.message))
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: _onNavigationRequest));

    final platform = controller.platform;
    if (platform is WebKitWebViewController) {
      platform.setInspectable(inspectable);
      platform.setAllowsBackForwardNavigationGestures(false);
    }
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(inspectable);
      platform.setMediaPlaybackRequiresUserGesture(false);
      final onShow = callbacks.onShowFullscreen;
      if (onShow != null) {
        platform.setCustomWidgetCallbacks(
          onShowCustomWidget: (widget, onHidden) => onShow(widget, onHidden),
          onHideCustomWidget: () => callbacks.onHideFullscreen?.call(),
        );
      }
    }
    controller.setOverScrollMode(WebViewOverScrollMode.never);
  }

  final TiptapSessionCallbacks callbacks;
  late final WebViewController controller;
  Uri? _pageUrl;

  /// True between [loadHtml] and the page's first navigation: the one navigation the main frame may make.
  bool _expectingLoad = false;

  Future<NavigationDecision> _onNavigationRequest(NavigationRequest request) async {
    final url = Uri.tryParse(request.url);
    if (url == null) return NavigationDecision.prevent;
    if (request.isMainFrame && _expectingLoad && (_isPage(url) || url.scheme == 'about')) {
      // The host page loading. Afterwards the main frame stays put: a second load of the base URL would
      // fetch the real site at that address, and give it the bridge.
      _expectingLoad = false;
      return NavigationDecision.navigate;
    }
    final allowed = await callbacks.onNavigation(TiptapNavigation(url: url, isMainFrame: request.isMainFrame));
    return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  bool _isPage(Uri url) {
    final page = _pageUrl;
    return page != null && url.removeFragment() == page.removeFragment();
  }

  @override
  Future<void> loadHtml(String html, {required Uri baseUrl}) {
    _pageUrl = baseUrl;
    _expectingLoad = true;
    return controller.loadHtmlString(html, baseUrl: baseUrl.toString());
  }

  @override
  Future<void> runJavaScript(String source) => controller.runJavaScript(source);

  @override
  Widget build(BuildContext context, {required Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers}) =>
      WebViewWidget(controller: controller, gestureRecognizers: gestureRecognizers);

  @override
  void dispose() {
    // The controller has no dispose; dropping the widget releases the platform view.
    _pageUrl = null;
  }
}
