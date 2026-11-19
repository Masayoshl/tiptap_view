# tiptap_view

Shows TipTap documents in Flutter: HTML, as published pages store it, or TipTap JSON. A WebView renders
the document with the same schema and extensions as the web editor; the Flutter page around it scrolls,
and the view grows to the height of its content. Read-only for now.

```dart
TiptapView(
  content: TiptapContent.html(html),            // or TiptapContent.json(map)
  onLinkTap: (link) => ...,                     // the view never navigates by itself
  onImageTap: (image) => ...,
)
```

## Installation

Until the package is on pub.dev, depend on its git repository:

```yaml
dependencies:
  tiptap_view:
    git:
      url: https://github.com/Masayoshl/tiptap_view.git
      ref: v0.1.0
```

## How it fits together

- **`js/`**: the runtime that runs in the page: the bridge to Dart, sanitizing, link and image taps,
  YouTube previews that become a player on tap (one at a time), height reports. Tests: `npm test`.
- **Bundles**: `runtime.js` + `runtime.css`, built with esbuild. The package ships a default bundle
  (`assets/default/`, StarterKit, images, tables, YouTube, text styles, alignment, task lists).
  An app with its own extensions writes an entry that calls `createRuntime` and builds it:
  `node js/build.mjs --entry path/to/entry.js --out path/to/assets/dir`, then
  `TiptapBundle.asset('path/to/assets/dir')`. See `example/tiptap/entry.js`.
- **Modes and view hooks**: the runtime has a core (bridge, theme, height, schema conversions) and a mode
  that owns the document's DOM; today that is `view`. Behavior for particular content in the view, such as
  the YouTube preview, is a view hook (`createRuntime({ viewHooks: defaultViewHooks() })`), not core code.
- **`TiptapExtension`**: the Dart side of an extension in the bundle: the view reports a bundle that lacks
  it, routes the events it sends (`runtime.emit`) to its handlers, and answers its requests
  (`await runtime.request(name, payload)`) with its `requests` handlers.
- **`TiptapWebViewAdapter`**: the WebView behind the view. `WebViewFlutterAdapter` (the default) uses the
  official `webview_flutter`, with Swift Package Manager support on iOS.
- **Taps**: `onLinkTap` gets the href and the link's attributes; `onImageTap` gets the image, its index and
  where it is on screen (`globalRect`), so a viewer can fly it full screen while
  `TiptapViewController.setImageHidden` hides the original.
- **`TiptapTheme`**: colors and type as `--tv-*` CSS variables; `TiptapTheme.of(context)` follows the app.
  `TiptapFontFace` embeds an app font, since the WebView cannot see fonts bundled in Flutter.

## Safety

The page with the bridge only ever shows the document: markup is sanitized (no scripts, handlers or
`javascript:` URLs, iframes only over https and sandboxed), the main frame never navigates after loading,
and Dart drops messages without the page's random session token.

## Development

```
cd js && npm install && npm run build:all && npm test   # bundles and JS tests
flutter test                                            # Dart tests
cd example && flutter run                               # the sandbox app
```

See [ROADMAP.md](ROADMAP.md) for what comes next. MIT licensed.
