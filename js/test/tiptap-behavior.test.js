// Pins down what TipTap itself does with content its schema does not describe. The editor's
// compatibility check (roadmap 4.3) is built on these facts; if a TipTap upgrade changes one, this fails.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!doctype html><html><body><div id="editor"></div></body></html>', { url: 'https://tiptap-view.local/' });
for (const key of ['window', 'document', 'Element', 'HTMLElement', 'Node', 'DOMParser', 'getComputedStyle', 'MutationObserver']) {
  globalThis[key] = key === 'window' ? dom.window : dom.window[key];
}
const { Editor, generateHTML, getSchema } = await import('@tiptap/core');
const { defaultExtensions } = await import('../src/default-extensions.js');

const extensions = defaultExtensions();
const schema = getSchema(extensions);
const text = value => ({ type: 'text', text: value });

function editorWith(content, options = {}) {
  const warnings = [];
  const warn = console.warn;
  console.warn = (...args) => warnings.push(args.map(String).join(' '));
  try {
    const editor = new Editor({ element: document.getElementById('editor'), extensions: defaultExtensions(), content, ...options });
    return { editor, warnings };
  } finally {
    console.warn = warn;
  }
}

test('an unknown node type gives the editor an empty document, with only a console warning', () => {
  const { editor, warnings } = editorWith({
    type: 'doc',
    content: [{ type: 'paragraph', content: [text('kept?')] }, { type: 'callout', content: [{ type: 'paragraph', content: [text('x')] }] }],
  });
  assert.equal(editor.getText(), '', 'the whole document is gone, not only the callout');
  assert.ok(warnings.some(warning => /Invalid content/.test(warning)));
  editor.destroy();
});

test('an unknown mark type also gives an empty document', () => {
  const { editor } = editorWith({
    type: 'doc',
    content: [{ type: 'paragraph', content: [{ ...text('marked'), marks: [{ type: 'spoiler' }] }] }],
  });
  assert.equal(editor.getText(), '');
  editor.destroy();
});

test('attributes a node or mark does not declare are dropped without a word', () => {
  const json = {
    type: 'doc',
    content: [
      { type: 'paragraph', attrs: { textAlign: 'center', blockId: 'b1' }, content: [
        { ...text('link'), marks: [{ type: 'link', attrs: { href: '/x', 'data-page-id': '12' } }] },
      ] },
      { type: 'image', attrs: { src: 'a.png', width: 300, caption: 'A cat' } },
    ],
  };
  const doc = schema.nodeFromJSON(json);
  doc.check();
  const [paragraph, image] = doc.content.content;
  assert.equal(paragraph.attrs.textAlign, 'center', 'a declared attribute stays');
  assert.equal('blockId' in paragraph.attrs, false);
  assert.equal('data-page-id' in paragraph.firstChild.marks[0].attrs, false);
  assert.equal(image.attrs.width, 300, 'Image declares width and height in TipTap 3');
  assert.equal('caption' in image.attrs, false);
  // Declared attributes the JSON leaves out get their defaults: a link saved without a target comes back
  // with target="_blank" and the default rel.
  assert.equal(paragraph.firstChild.marks[0].attrs.target, '_blank');

  const { editor, warnings } = editorWith(json);
  assert.equal(editor.getText().trim(), 'link', 'the document opens');
  assert.equal(warnings.length, 0, 'nothing tells that attributes were lost');
  const saved = editor.getJSON();
  assert.deepEqual(Object.keys(saved.content[0].attrs), ['textAlign']);
  assert.equal(saved.content[1].attrs.caption, undefined);
  assert.doesNotMatch(generateHTML(json, extensions), /blockId|data-page-id|caption|A cat/);
  editor.destroy();
});

test('with enableContentCheck, unknown types throw instead, and undeclared attributes still pass', () => {
  assert.throws(() => editorWith({ type: 'doc', content: [{ type: 'callout' }] }, { enableContentCheck: true }).editor,
    /Invalid JSON content/);
  const { editor } = editorWith(
    { type: 'doc', content: [{ type: 'paragraph', attrs: { blockId: 'b1' }, content: [text('x')] }] },
    { enableContentCheck: true },
  );
  assert.equal(editor.getText().trim(), 'x');
  editor.destroy();
});
