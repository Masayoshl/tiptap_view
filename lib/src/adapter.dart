import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A navigation the page asked for. The view allows the host page itself and embedded frames and
/// blocks everything else, so the page with the bridge never leaves for another site.
@immutable
class TiptapNavigation {
  const TiptapNavigation({required this.url, required this.isMainFrame});

  final Uri url;
  final bool isMainFrame;
}

/// What the view needs from a session to react to the page.
@immutable
class TiptapSessionCallbacks {
  const TiptapSessionCallbacks({
    required this.onMessage,
    required this.onNavigation,
    this.onShowFullscreen,
    this.onHideFullscreen,
  });

  /// A message the page posted to the [channelName] channel.
  final void Function(String message) onMessage;

  /// Returns whether to allow [TiptapNavigation].
  final FutureOr<bool> Function(TiptapNavigation navigation) onNavigation;

  /// A player went fullscreen and handed over a widget to show, where the platform does it that way
  /// (Android). [onHidden] tells the page the fullscreen widget was closed.
  final void Function(Widget widget, VoidCallback onHidden)? onShowFullscreen;
  final VoidCallback? onHideFullscreen;
}

/// The WebView behind a [TiptapView]. The package ships one on `webview_flutter`
/// ([WebViewFlutterAdapter]); another WebView plugin can be used by implementing this interface.
abstract interface class TiptapWebViewAdapter {
  /// Creates the WebView for one view. [channelName] is the JavaScript channel the page posts to.
  TiptapWebViewSession createSession({required String channelName, required TiptapSessionCallbacks callbacks});
}

/// One WebView, owned by one view.
abstract interface class TiptapWebViewSession {
  /// Loads [html] as the page, with [baseUrl] as its address: relative links and images resolve against it,
  /// and embeds see its origin as the referrer.
  Future<void> loadHtml(String html, {required Uri baseUrl});

  Future<void> runJavaScript(String source);

  /// The platform view. [gestureRecognizers] are the gestures the WebView claims from the Flutter page
  /// around it; the rest, vertical scrolling included, stays with Flutter.
  Widget build(BuildContext context, {required Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers});

  void dispose();
}
