## Unreleased

Groundwork for the editor (roadmap 4.1). Bundles must be rebuilt: the protocol is now 2.

* The runtime is a core plus a mode; the host page says which mode starts, and `ready` reports it. The view
  refuses a bundle that cannot start in its mode.
* View-only DOM work (sanitized `innerHTML`, table boxes, lazy images, taps) lives in the view mode.
* View hooks (`viewHooks` in `createRuntime`, `runtime.view.use`): the YouTube preview is one, in
  `defaultViewHooks()`. App bundles that want it add `viewHooks: defaultViewHooks()`. Images a hook adds
  carry `data-tv-decoration` and are not counted as the document's images.
* Requests from the page to Dart: `runtime.request(name, payload)` returns a promise that
  `TiptapExtension.requests` handlers answer.

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
