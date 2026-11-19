import { Extension } from '@tiptap/core';
import { Plugin, PluginKey } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';

// Images being uploaded are not in the document: each one is a placeholder decoration at its place, which
// follows edits around it, and becomes an image node only once the app has its URL. So a pending or failed
// upload can never be saved by accident, and the package needs no attributes on the app's image node.

const key = new PluginKey('tiptapViewUploads');

function placeholder({ id, preview, failed, message, onRetry, onRemove }) {
  const box = document.createElement('span');
  box.className = `tv-upload ${failed ? 'tv-upload--failed' : 'tv-upload--pending'}`;
  box.dataset.uploadId = id;
  box.contentEditable = 'false';
  if (preview) {
    const image = document.createElement('img');
    image.className = 'tv-upload__preview';
    image.alt = '';
    image.src = preview;
    box.appendChild(image);
  }
  if (failed) {
    if (message) box.title = message;
    const button = (className, label, text, action) => {
      const element = document.createElement('button');
      element.type = 'button';
      element.className = className;
      element.setAttribute('aria-label', label);
      element.textContent = text;
      element.addEventListener('click', event => {
        event.preventDefault();
        action(id);
      });
      return element;
    };
    box.appendChild(button('tv-upload__retry', 'Retry upload', '↻', onRetry));
    box.appendChild(button('tv-upload__remove', 'Remove image', '×', onRemove));
  }
  return box;
}

/**
 * The placeholders' extension and what the editor mode does with them. [onRetry] and [onRemove] are called
 * with an upload's id when the user taps those buttons on a failed placeholder.
 */
export function createUploads({ onRetry, onRemove }) {
  const extension = Extension.create({
    name: 'tiptapViewUploads',
    addProseMirrorPlugins() {
      return [new Plugin({
        key,
        state: {
          init: () => DecorationSet.empty,
          apply(tr, set) {
            let next = set.map(tr.mapping, tr.doc);
            const action = tr.getMeta(key);
            if (!action) return next;
            const existing = next.find(undefined, undefined, spec => spec.id === action.id);
            // Read the old placeholder first: DecorationSet.remove empties the array it is given.
            const old = existing[0] ? { pos: existing[0].from, preview: existing[0].spec.preview } : null;
            if (existing.length) next = next.remove(existing);
            if (action.type === 'remove') return next;
            const pos = action.type === 'add' ? action.pos : old && old.pos;
            if (pos == null) return next;
            const failed = action.type === 'fail';
            const preview = action.type === 'add' ? action.preview : old.preview;
            const dom = placeholder({ id: action.id, preview, failed, message: action.message, onRetry, onRemove });
            return next.add(tr.doc, [Decoration.widget(pos, dom, { id: action.id, preview, failed, side: -1, ignoreSelection: true, stopEvent: () => true })]);
          },
        },
        props: { decorations: state => key.getState(state) },
      })];
    },
  });

  const find = (editor, id) => key.getState(editor.state).find(undefined, undefined, spec => spec.id === id)[0] || null;
  const dispatch = (editor, action) => editor.view.dispatch(editor.state.tr.setMeta(key, action).setMeta('addToHistory', false));

  return {
    extension,
    /** Puts a placeholder for upload [id] at the selection; [preview] is an image URL to show meanwhile. */
    begin(editor, id, preview = null) {
      dispatch(editor, { type: 'add', id, pos: editor.state.selection.from, preview });
    },
    /** Shows a failed upload as pending again, in its place: it is being tried again. */
    retry(editor, id) {
      if (find(editor, id)) dispatch(editor, { type: 'pending', id });
    },
    fail(editor, id, message = '') {
      if (find(editor, id)) dispatch(editor, { type: 'fail', id, message });
    },
    /** Where upload [id] waits, or null when it is gone (removed, or the document was replaced). */
    position: (editor, id) => (find(editor, id) || {}).from ?? null,
    remove(editor, id) {
      if (find(editor, id)) dispatch(editor, { type: 'remove', id });
    },
    counts(editor) {
      const all = key.getState(editor.state).find();
      const failed = all.filter(decoration => decoration.spec.failed).length;
      return { pending: all.length - failed, failed };
    },
  };
}
