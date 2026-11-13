import 'dart:convert';
import 'dart:math';

/// Builds the page the WebView loads: the bundle's styles and script inline, the session token, and the
/// two elements the runtime renders into.
abstract final class TiptapHostPage {
  static String build({required String js, required String css, required String token}) {
    final config = jsonEncode({'token': token});
    return '<!doctype html>'
        '<html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">'
        '<style>${_inStyle(css)}</style>'
        '<script>window.__tiptapViewConfig = $config;</script>'
        '</head><body><div id="tv-root"><div id="tv-content" class="tiptap-view-content"></div></div>'
        '<script>${_inScript(js)}</script>'
        '</body></html>';
  }

  /// A fresh random token for a session.
  static String newToken() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // Text that would close the element early. esbuild already avoids it in scripts; this is a safety net.
  static String _inScript(String js) =>
      js.replaceAllMapped(RegExp('</(script)', caseSensitive: false), (match) => '<\\/${match[1]}');

  static String _inStyle(String css) =>
      css.replaceAllMapped(RegExp('</(style)', caseSensitive: false), (match) => '<\\/${match[1]}');
}
