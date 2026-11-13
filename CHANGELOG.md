## 0.1.0

First version: the read-only view.

* `TiptapView` shows HTML or TipTap JSON in a WebView that grows to its content inside a Flutter page,
  and stays alive when a lazy list scrolls it away.
* Runtime bundles built with esbuild: the default one (StarterKit, images, tables, YouTube, text styles,
  alignment, task lists) and app bundles with their own extensions (`js/build.mjs --entry`).
* Sanitized markup, a main frame that never navigates after loading, session tokens on bridge messages.
* Taps: links (`onLinkTap`, with attributes such as `data-page-id`), images (`onImageTap`, with the image's
  rect on screen for flying it into a viewer, and `setImageHidden` to hide the original meanwhile).
* YouTube embeds as previews that become a player on tap, one playing at a time.
* `TiptapTheme` as `--tv-*` CSS variables, following the Material theme; `TiptapFontFace` embeds app fonts.
* `TiptapViewController`: HTML ↔ JSON with the bundle's schema, the shown HTML, methods a bundle registers.
* `TiptapExtension`: names an extension the app relies on and routes the events it sends to Dart.
* `TiptapWebViewAdapter`, with `WebViewFlutterAdapter` on the official `webview_flutter` (Swift Package
  Manager on iOS).
