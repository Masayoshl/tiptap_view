import { Editor, Extension, generateJSON, getMarkRange, getSchema } from '@tiptap/core';
import { TableView } from '@tiptap/extension-table';
import { Plugin, PluginKey } from '@tiptap/pm/state';
import { incompatibility } from './compatibility.js';
import { createUploads } from './uploads.js';

const EMPTY = { type: 'doc', content: [{ type: 'paragraph' }] };
const CHANGE_DELAY = 150;
const STATE_DELAY = 30;

// Wide tables scroll sideways inside a wrapper of their own. A node view from a plugin is only a fallback:
// ProseMirror prefers the node views extensions give directly, so an app's own table view still wins.
const TableScroll = Extension.create({
  name: 'tiptapViewTableScroll',
  addProseMirrorPlugins() {
    if (!this.editor.schema.nodes.table) return [];
    return [new Plugin({
      key: new PluginKey('tiptapViewTableScroll'),
      props: { nodeViews: { table: (node, view) => new TableView(node, 25, view) } },
    })];
  },
});

/**
 * The editor: a TipTap `Editor` in `#tv-content`, with the bundle's extensions. ProseMirror owns this DOM,
 * so nothing here changes it by hand, and content goes in through the schema only (the schema's parse is
 * the sanitizer).
 *
 * Options from `createRuntime`, all written in JS next to the app's extensions and built into its bundle:
 *
 * - `editorExtensions`: extensions that only matter while editing (Placeholder, CharacterCount…). They
 *   must not add nodes or marks: the view and the editor share one schema.
 * - `normalizeContent(json, extensions)`: turns every document into the shape the app's editor expects
 *   before it is edited (the same function its web editor runs, so both get the same document).
 * - `validateForSave(editor)`: what keeps the document from being saved now, as a list; `getContent`
 *   returns it as `errors`, after the editor's own (`uploading`, `uploadFailed`).
 * - `embeds`: functions `(url, { schema, editor }) => node JSON | null` that turn a URL into an embed node;
 *   the first that returns a node wins (`insertEmbed`).
 *
 * The app answers, the package never calls an API: images are uploaded by Dart (`beginUpload` then
 * `finishUpload` or `failUpload`, or the `imageUpload` request for a pasted image), links are edited with
 * what the app's own UI asked for (`setLink`), and an embed is a URL the app got from the user.
 *
 * A document is opened with `setContent`. Each one starts a fresh editor, so undo never reaches into the
 * previous document.
 *
 * Commands are TipTap's own, by name (`toggleBold`, `setLink`, an app extension's `insertCallout`…), so the
 * package needs no code per command. After each transaction the editor sends a `state` event for toolbars,
 * built from the schema's names, so an app's own nodes and marks show up in it too.
 */
export function createEditorMode(core, { editorExtensions = [], normalizeContent = null, validateForSave = null, embeds = [] } = {}) {
  const { extensions, content, emit, request, reportError, reportHeight, schemaFor, schemaVersion } = core;
  const all = [...extensions, ...editorExtensions];

  if (editorExtensions.length) {
    const names = schema => [...Object.keys(schema.nodes), ...Object.keys(schema.marks)];
    const shared = new Set(names(schemaFor()));
    const added = names(getSchema(all)).filter(name => !shared.has(name));
    if (added.length) {
      reportError(new Error(`editorExtensions must not change the schema; they add: ${added.join(', ')}`), 'editorExtensions');
    }
  }

  let editor = null;
  let version = 0;
  let changeTimer = null;
  let stateTimer = null;
  let lastState = '';
  let imagePaste = false;
  let pasteCount = 0;
  // Pasted images, kept until they are uploaded, so a failed upload can be tried again.
  const pasted = new Map();

  const uploads = createUploads({
    onRetry: id => {
      uploads.retry(editor, id);
      if (pasted.has(id)) void uploadPasted(id);
      else emit('uploadRetry', { id });
    },
    onRemove: id => {
      uploads.remove(editor, id);
      pasted.delete(id);
      emit('uploadCancel', { id });
    },
  });

  function changed() {
    version += 1;
    clearTimeout(changeTimer);
    changeTimer = setTimeout(() => emit('change', { version }), CHANGE_DELAY);
  }

  /** What a toolbar needs to know, from the selection and the schema. */
  function describe() {
    const { state } = editor;
    const { selection } = state;
    const marks = {};
    for (const name of Object.keys(state.schema.marks)) {
      if (editor.isActive(name)) marks[name] = { ...editor.getAttributes(name) };
    }
    // The nodes around the selection, outermost first: the block type, lists, tables, alignment.
    const nodes = [];
    for (let depth = 1; depth <= selection.$from.depth; depth += 1) {
      const node = selection.$from.node(depth);
      nodes.push({ type: node.type.name, attrs: { ...node.attrs } });
    }
    const can = editor.can();
    return {
      version,
      editable: editor.isEditable,
      focused: editor.isFocused,
      marks,
      nodes,
      canUndo: typeof can.undo === 'function' && can.undo(),
      canRedo: typeof can.redo === 'function' && can.redo(),
      selection: {
        empty: selection.empty,
        from: selection.from,
        to: selection.to,
        // A selected node (an image, a video) rather than text.
        node: selection.node ? selection.node.type.name : null,
      },
    };
  }

  function stateChanged() {
    clearTimeout(stateTimer);
    stateTimer = setTimeout(() => {
      if (!editor) return;
      const state = describe();
      const text = JSON.stringify(state);
      if (text === lastState) return;
      lastState = text;
      emit('state', state);
    }, STATE_DELAY);
  }

  function open(doc, editable) {
    clearTimeout(changeTimer);
    if (editor) editor.destroy();
    content.replaceChildren();
    version = 0;
    lastState = '';
    editor = new Editor({
      element: content,
      extensions: [...all, TableScroll, uploads.extension, PasteImages],
      content: doc,
      editable,
      onUpdate: changed,
      onTransaction: stateChanged,
      onFocus: stateChanged,
      onBlur: stateChanged,
    });
    // Plugins that normalize the document on a transaction (StarterKit's TrailingNode adds an empty
    // paragraph after a last block that is not one) would otherwise do it on the user's first tap, and an
    // untouched document would count as edited. Let them run now, outside the undo history.
    editor.view.dispatch(editor.state.tr.setMeta('addToHistory', false));
    clearTimeout(changeTimer);
    version = 0;
    stateChanged();
    reportHeight();
  }

  // Uploads ------------------------------------------------------------------------------------------

  /** Replaces upload [id]'s placeholder with the image node; false when the placeholder is gone. */
  function finishUpload(id, { src, attributes = {}, node = 'image' } = {}) {
    const active = current();
    const pos = uploads.position(active, id);
    if (pos == null) return false;
    const type = active.schema.nodes[node];
    if (!type) throw new Error(`The schema has no "${node}" node for an uploaded image`);
    const attrs = { src };
    const dropped = [];
    for (const [name, value] of Object.entries(attributes || {})) {
      if (name in type.attrs) attrs[name] = value;
      else dropped.push(name);
    }
    if (dropped.length) {
      reportError(new Error(`The "${node}" node does not declare ${dropped.join(', ')}; the uploaded image goes in without them`), 'finishUpload');
    }
    uploads.remove(active, id);
    pasted.delete(id);
    return active.chain().insertContentAt(pos, { type: node, attrs }).run();
  }

  function readFile(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(reader.error || new Error('Could not read the image'));
      reader.readAsDataURL(file);
    });
  }

  /** Asks Dart to upload pasted image [id]; a failure leaves a placeholder that can be tried again. */
  async function uploadPasted(id) {
    const file = pasted.get(id);
    if (!file) return;
    const target = editor;
    try {
      const result = await request('imageUpload', { data: file.dataUrl.slice(file.dataUrl.indexOf(',') + 1), type: file.type, name: file.name });
      if (editor === target) finishUpload(id, result || {});
    } catch (error) {
      if (editor === target) uploads.fail(target, id, String((error && error.message) || error));
    }
  }

  async function pasteImages(files) {
    for (const file of files) {
      const id = `paste-${++pasteCount}`;
      const dataUrl = await readFile(file);
      pasted.set(id, { dataUrl, type: file.type, name: file.name || '' });
      uploads.begin(current(), id, dataUrl);
      void uploadPasted(id);
    }
  }

  // A pasted image file (a screenshot, a photo copied in another app) is uploaded when the app handles
  // `imageUpload`; pasted HTML, images in it included, goes through the schema like any content.
  const PasteImages = Extension.create({
    name: 'tiptapViewPasteImages',
    addProseMirrorPlugins() {
      return [new Plugin({
        key: new PluginKey('tiptapViewPasteImages'),
        props: {
          handlePaste(_view, event) {
            const data = event.clipboardData;
            if (!imagePaste || !data) return false;
            const files = Array.from(data.files || []).filter(file => /^image\//.test(file.type));
            if (!files.length || (data.getData('text/html') || '').replace(/<[^>]*>/g, '').trim()) return false;
            event.preventDefault();
            pasteImages(files).catch(error => reportError(error, 'paste'));
            return true;
          },
        },
      })];
    },
  });

  // Links --------------------------------------------------------------------------------------------

  function linkRange(active) {
    const type = active.schema.marks.link;
    if (!type) throw new Error('The schema has no "link" mark');
    const { $from } = active.state.selection;
    return { type, range: getMarkRange($from, type) || null };
  }

  function getLink() {
    const active = current();
    const { range } = linkRange(active);
    const { selection, doc } = active.state;
    if (!range) {
      return { active: false, href: null, attributes: {}, text: doc.textBetween(selection.from, selection.to, ' '), empty: selection.empty };
    }
    const { href = null, ...attributes } = active.getAttributes('link');
    return { active: true, href, attributes, text: doc.textBetween(range.from, range.to, ' '), empty: selection.empty };
  }

  function setLink({ href, attributes = {}, text = null }) {
    const active = current();
    const { type, range: inLink } = linkRange(active);
    const undeclared = Object.keys(attributes || {}).filter(name => !(name in type.attrs));
    if (undeclared.length) throw new Error(`The link mark does not declare ${undeclared.join(', ')}; they would be dropped`);
    const attrs = { ...attributes, href };
    const { selection } = active.state;
    const range = inLink || (selection.empty ? null : { from: selection.from, to: selection.to });
    const chain = active.chain().focus();
    if (text != null || !range) {
      // New text, or a link where nothing is selected: the text carries the link.
      const at = range || { from: selection.from, to: selection.from };
      return chain.insertContentAt(at, { type: 'text', text: text ?? href, marks: [{ type: 'link', attrs }] }).run();
    }
    return chain.setTextSelection(range).setLink(attrs).run();
  }

  // Embeds -------------------------------------------------------------------------------------------

  function insertEmbed({ url }) {
    const active = current();
    for (const resolve of embeds) {
      const node = resolve(String(url), { schema: active.schema, editor: active });
      if (node) {
        const inserted = active.chain().focus().insertContent(node).run();
        return { inserted, type: node.type };
      }
    }
    return { inserted: false, type: null };
  }

  function commandArguments(args) {
    if (args == null) return [];
    return Array.isArray(args) ? args : [args];
  }

  // The editor places the caret on a tap; a link opens only through an action of the app, which hears of
  // the tap (to show a bubble with the link, for one).
  document.addEventListener('click', event => {
    const link = event.target instanceof Element && event.target.closest('a');
    if (!link || !content.contains(link)) return;
    event.preventDefault();
    const attributes = {};
    for (const attribute of Array.from(link.attributes)) attributes[attribute.name] = attribute.value;
    emit('linkTap', { href: link.getAttribute('href') || '', text: link.textContent || '', attributes });
  }, true);

  function current() {
    if (!editor) throw new Error('No document is open; call setContent first');
    return editor;
  }

  function saveErrors() {
    const active = current();
    const { pending, failed } = uploads.counts(active);
    const errors = [];
    if (pending) errors.push({ code: 'uploading', count: pending });
    if (failed) errors.push({ code: 'uploadFailed', count: failed });
    const own = validateForSave ? validateForSave(active) : null;
    if (own) errors.push(...(Array.isArray(own) ? own : [own]));
    return errors;
  }

  return {
    current: () => editor,
    methods: {
      setContent({ format, content: value, schemaVersion: documentVersion = null, editable = true }) {
        let json;
        if (format === 'json') {
          json = typeof value === 'string' ? JSON.parse(value) : value;
          const problem = incompatibility(json, schemaFor(), { documentVersion, bundleVersion: schemaVersion });
          if (problem) {
            open(EMPTY, false);
            return { status: 'incompatible', ...problem };
          }
        } else {
          // HTML from before TipTap: what the schema drops is the accepted cost, as on the web.
          json = generateJSON(String(value ?? ''), extensions);
        }
        if (normalizeContent) json = normalizeContent(json, all);
        // Throws on a document the schema rejects, instead of letting TipTap open an empty one.
        schemaFor().nodeFromJSON(json).check();
        open(json, editable);
        return { status: 'ok' };
      },
      getContent() {
        const active = current();
        return { json: active.getJSON(), html: active.getHTML(), version, errors: saveErrors() };
      },
      setEditable({ editable }) {
        current().setEditable(Boolean(editable));
        stateChanged();
      },
      /** Runs TipTap's command [name] with [args] (one value or a list), focused first unless [focus] is false. */
      command({ name, args = null, focus = true }) {
        const chain = current().chain();
        if (typeof chain[name] !== 'function') throw new Error(`Unknown command: ${name}`);
        const run = focus ? chain.focus() : chain;
        return run[name](...commandArguments(args)).run();
      },
      /** Whether [name] with [args] would do something now: for disabled toolbar buttons. */
      canRun({ name, args = null }) {
        const can = current().can();
        if (typeof can[name] !== 'function') throw new Error(`Unknown command: ${name}`);
        return Boolean(can[name](...commandArguments(args)));
      },
      /** The names of the commands the open document's extensions have. */
      commands: () => Object.keys(current().commands).sort(),
      /** The toolbar state now, as the `state` event sends it. */
      getState: () => describe(),
      focus({ position = 'end' } = {}) {
        current().commands.focus(position);
      },
      blur() {
        current().commands.blur();
      },
      beginUpload({ id, preview = null }) {
        uploads.begin(current(), String(id), preview);
      },
      finishUpload: ({ id, ...result }) => finishUpload(String(id), result),
      failUpload({ id, message = '' }) {
        uploads.fail(current(), String(id), message);
      },
      retryUpload({ id }) {
        uploads.retry(current(), String(id));
      },
      cancelUpload({ id }) {
        uploads.remove(current(), String(id));
      },
      setImagePaste({ enabled }) {
        imagePaste = Boolean(enabled);
      },
      getLink: () => getLink(),
      setLink: params => setLink(params),
      removeLink: () => current().chain().focus().extendMarkRange('link').unsetLink().run(),
      insertEmbed: params => insertEmbed(params),
    },
  };
}
