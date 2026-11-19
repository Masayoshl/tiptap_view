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

## 3. Sharing the schema with the web (a guide, not package code)

The schema belongs to the app, so this stage is documentation and checks the package offers, not work
inside it.

- [ ] README: how an app keeps its extensions in one place both its web editor and its bundle import
      (data only: `attrs`, `parseHTML`, `renderHTML`, commands; node views and UI stay per platform), and
      passes its schema version to `createRuntime`.
- [ ] A round-trip check an app can run on its bundle and a folder of its documents: `html → json → html`
      and `json → html → json` do not change (`node js/check-schema.mjs --entry … --docs …`). The editor's
      lossy-content check (4.3) uses the same comparison.

## 4. Editor

The editor is the same runtime and the same bundle in another mode. Everything the view does to the DOM
by itself (wrapping tables, embed previews, catching taps) is view-only, because in the editor ProseMirror
owns the DOM. The stages below are in order: each one is usable and tested before the next.

### 4.1 Runtime modes (groundwork, no editor yet)

- [x] Split `runtime.js` into a core (bridge, methods, events, theme, height, errors) and modes. The
      host page config says which mode starts: `view` (today's behavior) or `editor`.
- [x] View-only code moves into the view mode: `render` through `innerHTML`, table boxes, lazy images,
      tap capture, `setImageHidden`.
- [x] Take YouTube out of the core. A bundle adds view behavior through a hook
      (`createRuntime({ viewHooks })` or `runtime.view.use({ prepare(root), click(target, event) })`); the YouTube preview becomes one
      such hook, registered by the default bundle. The core no longer knows `.tv-embed--youtube` or
      `.tv-embed__poster`.
- [x] A JS → Dart call that waits for an answer (`{type: "request", id, name, payload}` and Dart's
      response), next to events. The editor's hooks (4.4) need it.
- [x] `PROTOCOL_VERSION` 2; the view keeps working unchanged on it.

### 4.2 Editing core

- [ ] Editor mode: `new Editor({ element, extensions, content, editable })` in `#tv-content`, with the
      bundle's extensions. Sanitizing is the schema's parse: content goes in through the schema only.
- [ ] `TiptapEditor` widget + `TiptapEditorController`: `setContent` / `getHtml` / `getJson`,
      `editable`, `focus` / `blur`, `clear`. `TiptapContent` is reused for the input.
- [ ] Changes: a debounced `change` event with a document version; the controller reads HTML or JSON
      on demand rather than every keystroke shipping the whole document.
- [ ] Commands, generic first: `controller.command('toggleBold')`, `command('setLink', {href})`, run
      through `editor.chain().focus()[name](args).run()`; `canRun(name, args)` for disabled states.
      Typed shortcuts (`toggleBold()`, `setHeading(level)`) on top, only for StarterKit's commands.
- [ ] Toolbar state: a `state` event after each transaction, with active marks and nodes (with attrs,
      for headings and alignment), `canUndo` / `canRedo`, selection (empty, inside a link, a node
      selection). Computed from the schema's names, so an app's own nodes show up without code here.
- [ ] Taps in the editor place the caret; links open only through an app action (a link bubble),
      never on a tap.

### 4.3 Content that would be lost

- [ ] JSON with node or mark types outside the schema: refuse to edit, open read-only, say which.
- [ ] HTML that the schema cannot keep (legacy markup: divs with styles, unknown classes): compare
      `sanitize(html)` with `generateHTML(generateJSON(html))` after normalizing, report what is lost
      (tags, attributes, how many), and open read-only unless the app passes `allowLossyEdit: true`
      after showing that to the user.
- [ ] Tests on fixtures: clean TipTap HTML is never reported as lossy; legacy HTML always is.

### 4.4 Hooks (the app answers, the package never calls an API)

- [ ] Images: `onImageUpload(file) → Future<Uri>`; the editor shows a placeholder node while it waits and
      removes it on failure. Picking the file stays with the app.
- [ ] Links: `onLinkEdit(current) → Future<TiptapLinkEdit?>` with `href` and any attributes the app adds
      (`data-*`), so internal links are the app's business, not a link type in the package.
- [ ] Embeds: `onEmbedInsert() → Future<String?>` returns a URL; the bundle's extensions decide which node
      it becomes (YouTube, iframe…), or the editor reports that none accepts it.
- [ ] Paste: pasted HTML goes through the schema like any content; pasted images go through
      `onImageUpload`.

### 4.5 Layout and keyboard

- [ ] Two layouts: the editor grows with its content inside the app's scrollable (like the view) and
      reports the caret's rect so the app can keep it above the keyboard; or it has a fixed height and
      scrolls itself. Measure both on real devices and pick the default.
- [ ] iOS: focus from Dart, scrolling to the caret, the input accessory bar (hide it or replace it with
      the Flutter toolbar). If `webview_flutter` cannot do this, a second adapter.
- [ ] Android: IME composition (Gboard, CJK input), selection handles inside the Flutter page.
- [ ] Undo and redo from the keyboard shortcuts and from the toolbar stay in one history.

### 4.6 Toolbar building blocks

- [ ] Flutter widgets bound to the controller's state: a mark toggle, a block type menu, undo / redo, a
      link button. The app composes its own toolbar; the package ships no fixed one.
- [ ] `TiptapExtension` can carry its own toolbar items and command names, so an app's node comes with
      its button.

### 4.7 Example and tests

- [ ] The example gets an editor screen: edit, save to JSON and HTML, open the saved document in
      `TiptapView`, the same bundle in both.
- [ ] JS tests of the editor mode on jsdom; Dart tests of the controller with the fake session, as for
      the view.

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
