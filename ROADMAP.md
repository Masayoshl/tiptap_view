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
          ref: v0.4.0
      ```
- [ ] `homepage` / `repository` in `pubspec.yaml`; drop `publish_to: none` when publishing to pub.dev.
- [ ] CI: `flutter test`, `npm test` in `js/`, `flutter analyze`, and a check that the committed bundles in
      `assets/` match a fresh `npm run build:all` (a stale bundle is the easiest mistake to ship).

## 2. Finish the view

- [x] Run the example on Android: layout, link and image taps, YouTube inline and fullscreen
      (`setCustomWidgetCallbacks`). The keep-alive in lists is still to check.
- [ ] Very long documents: memory and first paint of a WebView several screens tall, on both platforms.
      If it hurts, render in slices or let the view scroll itself with the page's header passed in.
- [ ] In-page anchors (`#section`): report the target's offset so the app can scroll its page to it.
- [ ] Text selection and copy, accessibility (VoiceOver / TalkBack over the WebView content).
- [ ] Wide tables: horizontal scroll inside the table box on real TipTap tables (`colgroup` widths).
- [ ] Decide the default extension set (Highlight, Details, Subscript…) against what common editors emit.
- [x] Sanitizer allowances from the bundle (`createRuntime({ sanitize: { addTags, addAttributes } })`):
      an app node that renders an element the sanitizer forbids, such as embedify's
      `button[data-video-time]` timestamps, stays in the view. Elements that run or load code (`script`,
      `style`, `object`, `embed`, `base`, `meta`, `link`, `form`, `svg`…) and `on*` attributes are refused
      with an error.
- [x] No flash before the first height: the loading builder stays until the content is in and measured,
      and the WebView draws no scrollbar of its own.
- [ ] Warm a page ahead of time (a pool of one preloaded WebView) so the first document shows faster.

## 3. Sharing the schema with the web (a guide, not package code)

The schema belongs to the app, so this stage is documentation and checks the package offers, not work
inside it.

- [ ] README: how an app keeps its extensions in one place both its web editor and its bundle import
      (data only: `attrs`, `parseHTML`, `renderHTML`, commands; node views and UI stay per platform), and
      passes its schema version to `createRuntime`.
- [ ] README: when to bump the schema version. TipTap schemas have no version of their own; the number is
      the app's promise. Bump it on any change an older client would not keep: a new node, mark or
      attribute, changed nesting rules. Visual changes (CSS, node views) keep it.
- [ ] README: what an app stores and feeds back. Save `json`, the schema's `html` and the schema version
      together; open the JSON when there is one, and HTML only for documents from before TipTap.
- [ ] A round-trip check an app can run on its bundle and a folder of its documents: `html → json → html`
      and `json → html → json` do not change (`node js/check-schema.mjs --entry … --docs …`). The editor's
      loss report (4.3) uses the same comparison.

## 4. Editor

Two widgets, one bundle:

- `TiptapView` and `TiptapEditor` are separate widgets with their own controllers and callbacks; there is
  no `editable` flag on the view. What they share (loading the bundle, the token, the bridge, requests,
  theme, height, errors) is a private page host both are built on.
- One bundle carries both modes, so the view and the editor always have the same schema. Extensions
  that only matter while editing (Placeholder, CharacterCount, menus) go in
  `createRuntime({ editorExtensions })` and never change the schema. A view-only or editor-only bundle
  can come later if someone needs one; the `mode` handshake already covers it.
- Everything the view does to the DOM by itself (wrapping tables, embed previews, catching taps) is
  view-only, because in the editor ProseMirror owns the DOM.

The stages below are in order: each one is usable and tested before the next.

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
- [x] One copy of TipTap in an app bundle: `build.mjs` resolves every `@tiptap/*` and `prosemirror-*`
      import to the runtime's copy when it has one, so extensions from the app's own repository (with
      their own `node_modules`) do not bring a second schema implementation. Tried on embedify's schema:
      970 KB with two copies, 550 KB with one.
- [ ] `youtubePreview` lets other hooks start a player (`activate(src)`), so a hook that seeks a video
      from a timestamp can start it first instead of turning previews off.

### 4.2 Editing core

- [x] Move the page host out of `_TiptapViewState` (load, token, bridge, requests, theme, height, errors),
      so `TiptapView` and `TiptapEditor` share it; the view's tests stay as they are.
- [x] Conversions both controllers have (`htmlToJson`, `jsonToHtml`, `nodeTypes`) in a shared base.
- [x] Editor mode: `new Editor({ element, extensions, content, editable })` in `#tv-content`, with the
      bundle's extensions. Sanitizing is the schema's parse: content goes in through the schema only.
- [x] `TiptapEditor` widget + `TiptapEditorController`: `content` opens a document (each new value afresh,
      with a new undo history), `editable`, `getContent()`, `focus` / `blur`. `TiptapContent` is reused for
      the input. The editor mode adds about 23 KB to a bundle.
- [x] Changes: a debounced `change` event with a document version; the controller reads HTML or JSON
      on demand rather than every keystroke shipping the whole document.
- [x] Commands, generic first: `controller.command('toggleBold')`, `command('setLink', {href})`, run
      through `editor.chain().focus()[name](args).run()`; `canRun(name, args)` for disabled states;
      `commands()` lists them.
- [ ] Typed shortcuts (`toggleBold()`, `setHeading(level)`) on top, only for StarterKit's commands:
      with the toolbar building blocks (4.6), when it is clear which ones they need.
- [x] Toolbar state: a `state` event after each transaction, with active marks and nodes (with attrs,
      for headings and alignment), `canUndo` / `canRedo`, selection (empty, inside a link, a node
      selection). Computed from the schema's names, so an app's own nodes show up without code here.
- [x] Taps in the editor place the caret; links open only through an app action (a link bubble),
      never on a tap.
- [x] Wide tables in the editor scroll inside their own box: a fallback table node view (TipTap's
      `TableView`, from a plugin, so an app's own table view still wins), as `tv-table-scroll` does in
      the view.
- [x] Document functions from the app's bundle, written in JS next to its extensions and built into the
      bundle (Dart never sends code): `createRuntime({ normalizeContent, validateForSave })`.
      `normalizeContent(json)` runs on every document going into the editor, so the web and the app
      turn the same HTML into the same document. `validateForSave(editor)` runs in `getContent()`,
      which returns `{json, html, errors}`; form rules (title, permissions, revisions) stay in Dart.
- [x] Pin down TipTap's own behavior with tests before building on it (`js/test/tiptap-behavior.test.js`,
      TipTap 3.31):
      - an unknown node or mark type in JSON: with `enableContentCheck` off (the default) a console
        warning and an **empty document**; with it on, an exception. So the 4.3 check runs before
        content reaches the editor.
      - attributes a node or mark does not declare: dropped silently, with or without
        `enableContentCheck`; the saved JSON and HTML no longer have them. TipTap does not see this, so
        the 4.3 check compares attribute keys with the schema too.
      - declared attributes the JSON leaves out get their defaults on load: a link without `target`
        is saved back with `target="_blank"` and the default `rel`.

### 4.3 Documents the schema cannot hold

The rule: the document and the bundle each say what schema they need, and when they do not agree the
editor refuses to edit. The package says why, in neutral terms; what the user is told (and whether an
update would help) is the app's call, since the package cannot know whether a newer app exists.

- [x] Structural check, always: node and mark types in the JSON that the bundle's schema lacks, and
      attribute keys a node or mark does not declare (the check embedify's web editor already does in
      `isSupportedPageDocument`). A walk of the JSON: well under a millisecond for 20,000 nodes.
- [x] Version check, when the app passes the document's version (`TiptapContent.json(map,
      schemaVersion: 2)`; it is stored next to the JSON, not inside it): a document newer than the
      bundle's `schemaVersion`.
- [x] Either one: the editor does not start editing and reports
      `TiptapIncompatibleContent(reason: newerSchema | unknownTypes | unknownAttributes, types: […],
      attributes: […], documentVersion, bundleVersion)`.
      The app shows the document another way, `TiptapView` with the HTML the web saved for one.
- [ ] HTML from before TipTap is converted through the schema, as the web editor does on the first edit;
      what the schema drops is the product's accepted cost. An optional `onContentLoss` report (what was
      dropped) for apps that want to tell the user; it never blocks.

### 4.4 Hooks (the app answers, the package never calls an API)

The app drives what it starts (its toolbar, its dialogs) through the controller; the editor calls the app
only for what starts in the page (a paste, a tap).

- [x] Images: `controller.uploadImage(upload, preview:)`. A placeholder decoration waits at the selection,
      outside the document (so it can never be saved by accident, and the app's image node needs no
      upload attributes), follows edits around it, and becomes the app's image node
      (`TiptapUploadedImage(src, attributes:, node:)`, `blockImage` and `data-media-id` for embedify) once
      the upload returns. A failure shows Retry (runs `upload` again) and Remove. Pending and failed ones
      are `uploading` / `uploadFailed` in `getContent().errors`. Picking the file stays with the app.
- [x] Links: `getLink()` (the link at the selection, or the selected text), `setLink(href, attributes:,
      text:)`, `removeLink()`; the app's dialog sits in between. Attributes are the link mark's own names
      (embedify's `pageId` renders `data-page-id`); ones it does not declare are refused, not lost.
      `onLinkTap` reports taps on links in the editor, which never follows them.
- [x] Embeds: `insertEmbed(url)` with the bundle's resolvers (`createRuntime({ embeds })`,
      `defaultEmbeds()` for YouTube); returns the node type, or null when none knows the URL.
- [x] Paste: pasted HTML goes through the schema like any content; a pasted image file goes to
      `onImageUpload(TiptapImageFile)` with a placeholder of its own, retried by the page itself.
- [ ] Later, opt-in: `data:` and `blob:` images inside pasted HTML uploaded in place.
- [ ] Extension options that call an API on the web (`fetchTranscript`, `translate`) become requests:
      `fetchTranscript: src => runtime.request('fetchTranscript', { src })`, answered by a
      `TiptapExtension` in Dart. A README recipe, no new code.

### 4.5 Layout and keyboard

- [x] The editor grows with its content inside the app's scrollable, like the view. The runtime reports
      the caret (`caret` event, in the view's coordinates) while the editor has focus, and the editor
      scrolls the page around it to keep the caret in sight (`keepCaretVisible`, `caretPadding`): when
      the caret moves, and while the keyboard grows. Only a growing inset counts, since iOS also reports
      metrics while the page scrolls under a focused field. Checked on the iOS simulator with the
      on-screen keyboard.
- [x] The page in the WebView never scrolls by itself: iOS scrolled it on focus, which hid the top of
      the document out of reach of any drag. Any page scroll is undone at once.
- [ ] A fixed-height layout that scrolls itself, for apps that want the editor as a pane; measure it
      against the growing one on real devices.
- [x] iOS: the input accessory bar above the keyboard (arrows, Done) takes ~50pt and duplicates the app's
      toolbar. `showKeyboardAccessory: false` hides it, through a small iOS plugin (Swift Package Manager,
      a podspec too) that replaces the `inputAccessoryView` getter of WebKit's `WKContentView`. A private
      class: the plugin does nothing when it is gone.
- [x] iOS: focusing the editor from code (a toolbar button) moved the caret and left the keyboard down; WebKit
      shows it only for a focus the user started in the page. `focusShowsKeyboard` (on by default) has the
      plugin tell `WKContentView`'s `_elementDidFocus:userIsInteracting:…` the user is interacting. A private
      method: the plugin does nothing when it is gone. Checked on the iOS 26 simulator.
- [x] Android: Gboard composition works. Selection handles are drawn by the WebView in a window of their
      own at a fixed place on screen and stayed behind, over the keyboard, when the page scrolled; the
      editor now drops them on the first scroll of the page while it has focus.
- [ ] CJK input on Android and iOS.
- [ ] Undo and redo from the keyboard shortcuts and from the toolbar stay in one history.

### 4.6 Toolbar building blocks

- [ ] Flutter widgets bound to the controller's state: a mark toggle, a block type menu, undo / redo, a
      link button. The app composes its own toolbar; the package ships no fixed one.
- [ ] `TiptapExtension` can carry its own toolbar items and command names, so an app's node comes with
      its button.

### 4.7 Example and tests

- [x] The example gets an editor screen: edit, save to JSON and HTML, open the saved document in
      `TiptapView`, the same bundle in both. Run on the iOS simulator (iPhone 17 Pro, iOS 26.2): typing,
      selection and the toolbar state, uploads with failure and Retry, embeds, Save into the view.
- [x] The same run on Android (Pixel 9 emulator, Gboard): view taps, YouTube inline and fullscreen and
      Back out of it, typing with Gboard composition, toolbar, uploads with failure and Retry, Save into
      the view, the caret above the keyboard. The iOS simulator with its on-screen keyboard too.
- [ ] A real iPhone and a real Android phone.
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
