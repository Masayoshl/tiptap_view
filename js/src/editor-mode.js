import { Editor, generateJSON, getSchema } from '@tiptap/core';
import { incompatibility } from './compatibility.js';

const EMPTY = { type: 'doc', content: [{ type: 'paragraph' }] };
const CHANGE_DELAY = 150;

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
 * - `validateForSave(editor)`: what keeps the document from being saved now (uploads still running, for
 *   one), as a list; `getContent` returns it as `errors`.
 *
 * A document is opened with `setContent`. Each one starts a fresh editor, so undo never reaches into the
 * previous document.
 */
export function createEditorMode(core, { editorExtensions = [], normalizeContent = null, validateForSave = null } = {}) {
  const { extensions, content, emit, reportError, reportHeight, schemaFor, schemaVersion } = core;
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

  function changed() {
    version += 1;
    clearTimeout(changeTimer);
    changeTimer = setTimeout(() => emit('change', { version }), CHANGE_DELAY);
  }

  function open(doc, editable) {
    clearTimeout(changeTimer);
    if (editor) editor.destroy();
    content.replaceChildren();
    version = 0;
    editor = new Editor({
      element: content,
      extensions: all,
      content: doc,
      editable,
      onUpdate: changed,
    });
    reportHeight();
  }

  // The editor places the caret on a tap; a link opens only through an action of the app.
  document.addEventListener('click', event => {
    const link = event.target instanceof Element && event.target.closest('a');
    if (link && content.contains(link)) event.preventDefault();
  }, true);

  function current() {
    if (!editor) throw new Error('No document is open; call setContent first');
    return editor;
  }

  function saveErrors() {
    if (!validateForSave) return [];
    const errors = validateForSave(current());
    if (!errors) return [];
    return Array.isArray(errors) ? errors : [errors];
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
      },
      focus({ position = 'end' } = {}) {
        current().commands.focus(position);
      },
      blur() {
        current().commands.blur();
      },
    },
  };
}
