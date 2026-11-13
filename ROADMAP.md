# Roadmap

What comes after 0.1.0, roughly in order. Each stage keeps the boundaries the package was built with:

- the package knows no app and no document schema: an app brings its extensions in its own bundle;
- the schema (what a document can contain, and how it reads from and writes to HTML) is shared with the
  web editor, never forked for mobile;
- the WebView sits behind `TiptapWebViewAdapter`, so it can be replaced without touching the rest.

## 1. Publish

- [ ] Put the package in its own GitHub repository; tag releases (`v0.1.0`).
- [ ] Apps depend on it through git until it is on pub.dev:
      ```yaml
      tiptap_view:
        git:
          url: https://github.com/<owner>/tiptap_view.git
          ref: v0.1.0
      ```
- [ ] `homepage` / `repository` in `pubspec.yaml`; drop `publish_to: none` when publishing to pub.dev.
- [ ] CI: `flutter test`, `npm test` in `js/`, `flutter analyze`, and a check that the committed bundles in
      `assets/` match a fresh `npm run build:all` (a stale bundle is the easiest mistake to ship).

## 2. Finish the view

- [ ] Run the example on Android: layout, link and image taps, YouTube inline and fullscreen
      (`setCustomWidgetCallbacks`), the keep-alive in lists.
- [ ] Very long documents: memory and first paint of a WebView several screens tall, on both platforms.
      If it hurts, render in slices or let the view scroll itself with the page's header passed in.
- [ ] In-page anchors (`#section`): report the target's offset so the app can scroll its page to it.
- [ ] Text selection and copy, accessibility (VoiceOver / TalkBack over the WebView content).
- [ ] Wide tables: horizontal scroll inside the table box on real TipTap tables (`colgroup` widths).
- [ ] Decide the default extension set (Highlight, Details, Subscript…) against what common editors emit.
- [ ] Warm a page ahead of time (a pool of one preloaded WebView) so the first document shows faster.

## 3. Share the schema with the web

- [ ] Move the app's extensions out of the web project into their own package (`@<app>/editor-schema`):
      data only (`attrs`, `parseHTML`, `renderHTML`, commands); node views and UI stay per platform.
- [ ] App bundles import that package; `SCHEMA_VERSION` from it goes into `createRuntime`.
- [ ] Round-trip tests in the schema package: `html → json → html` does not change.

## 4. Editor

- [ ] `TiptapEditor` + `TiptapEditorController`: the same runtime in editable mode.
- [ ] Content in and out as HTML and JSON; a change stream; commands (`toggleBold`, `setLink`,
      `insertTable`…) and a state stream for toolbars (active marks, can undo, block type).
- [ ] Toolbar building blocks in Flutter; the app composes its own toolbar.
- [ ] Hooks instead of API calls: upload an image and return its URL, pick a link target, insert an embed.
- [ ] Refuse to edit a document with nodes outside the loaded schema (open read-only and say so): saving
      it would drop them silently.
- [ ] iOS keyboard: focus, scrolling to the caret, the accessory bar above the keyboard. If
      `webview_flutter` cannot do what is needed, a second adapter.

## 5. Extensions as packages

- [ ] Build with `@tiptap/*` external, taken from the runtime (`window.TiptapRuntime`), so extensions can be
      separate bundles with one copy of TipTap in the page.
- [ ] `TiptapExtension` carries its JS and CSS assets; the view loads them after the runtime and before
      creating the schema.
- [ ] Extension packages (`tiptap_view_youtube`, `tiptap_view_details`…) that depend on `tiptap_view`;
      pub's version constraints keep them compatible with the runtime.
- [ ] A monorepo with pub workspaces for the package, its adapters and its extensions.

## 6. Native view (later, if needed)

- [ ] Render TipTap JSON with Flutter widgets: a builder per node name, registered by extensions.
- [ ] HTML input through the runtime's `generateJSON` in a hidden WebView, cached, instead of a second
      HTML parser in Dart.
- [ ] Embeds stay web: a preview widget and a WebView only for the one that plays.
