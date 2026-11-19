import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

// The runtime in a host page that asks for the editor mode, as TiptapEditor builds it.
const dom = new JSDOM('<!doctype html><html><body><div id="tv-root"><div id="tv-content"></div></div></body></html>', {
  url: 'https://tiptap-view.local/',
});
const { window } = dom;
for (const key of ['window', 'document', 'Element', 'HTMLElement', 'Node', 'DOMParser', 'CustomEvent', 'getComputedStyle', 'MutationObserver']) {
  globalThis[key] = key === 'window' ? window : window[key];
}
window.__tiptapViewConfig = { token: 'secret', mode: 'editor' };

const messages = [];
window.TiptapViewBridge = { postMessage: text => messages.push(JSON.parse(text)) };

let runtime;
let mod;
let saveProblems = [];
before(async () => {
  mod = await import('../src/index.js');
  const { Extension } = await import('@tiptap/core');
  runtime = mod.createRuntime({
    name: 'test',
    schemaVersion: 2,
    extensions: mod.defaultExtensions(),
    editorExtensions: [Extension.create({ name: 'editorOnly' })],
    // As an app normalizes: here, every heading below level 2 becomes level 2.
    normalizeContent: json => ({
      ...json,
      content: (json.content || []).map(node => (node.type === 'heading' && node.attrs.level < 2 ? { ...node, attrs: { ...node.attrs, level: 2 } } : node)),
    }),
    validateForSave: () => saveProblems,
  });
});

const content = () => window.document.getElementById('tv-content');
const events = name => messages.filter(message => message.type === 'event' && message.event === name);
const paragraph = text => ({ type: 'paragraph', content: [{ type: 'text', text }] });
const doc = (...blocks) => ({ type: 'doc', content: blocks });

async function call(method, params) {
  const id = `${method}-${messages.length}`;
  runtime.receive({ id, method, params });
  await new Promise(resolve => setTimeout(resolve, 0));
  const response = messages.find(message => message.type === 'response' && message.id === id);
  assert.ok(response, `no response to ${method}`);
  if (response.error) throw new Error(response.error);
  return response.result;
}

test('starts in the editor mode and has no document until one is set', async () => {
  const [ready] = events('ready');
  assert.equal(ready.payload.mode, 'editor');
  assert.equal(runtime.editor, null);
  await assert.rejects(call('getContent'), /No document is open/);
  assert.equal(events('error').length, 0, 'editorExtensions without nodes or marks are fine');
});

test('opens JSON for editing and gives it back with the HTML and its version', async () => {
  assert.deepEqual(await call('setContent', { format: 'json', content: doc(paragraph('Hello')), schemaVersion: 2 }), { status: 'ok' });
  assert.ok(content().querySelector('.ProseMirror[contenteditable="true"]'), 'ProseMirror owns the content element');
  const result = await call('getContent');
  assert.deepEqual(result.json, doc({ ...paragraph('Hello'), attrs: { textAlign: null } }));
  assert.equal(result.html, '<p>Hello</p>');
  assert.equal(result.version, 0);
  assert.deepEqual(result.errors, []);
});

test('counts edits and reports them after a pause', async () => {
  await call('setContent', { format: 'json', content: doc(paragraph('Hello')) });
  runtime.editor.commands.insertContentAt(1, 'Oh, ');
  runtime.editor.commands.insertContentAt(1, 'Well. ');
  assert.equal(events('change').length, 0, 'not on every keystroke');
  await new Promise(resolve => setTimeout(resolve, 200));
  assert.deepEqual(events('change').at(-1).payload, { version: 2 });
  assert.equal((await call('getContent')).html, '<p>Well. Oh, Hello</p>');
});

test('a new document starts a fresh editor: undo stays inside it', async () => {
  await call('setContent', { format: 'json', content: doc(paragraph('First')) });
  runtime.editor.commands.insertContentAt(1, 'Edited ');
  await call('setContent', { format: 'json', content: doc(paragraph('Second')) });
  assert.equal(runtime.editor.can().undo(), false);
  assert.equal((await call('getContent')).version, 0);
});

test('refuses JSON with types or attributes the schema lacks, and a newer schema version', async () => {
  const unknownType = await call('setContent', {
    format: 'json',
    content: doc(paragraph('x'), { type: 'callout', content: [paragraph('y')] }, { type: 'paragraph', content: [{ type: 'text', text: 'z', marks: [{ type: 'spoiler' }] }] }),
  });
  assert.equal(unknownType.status, 'incompatible');
  assert.equal(unknownType.reason, 'unknownTypes');
  assert.deepEqual(unknownType.types, ['callout', 'spoiler']);
  assert.equal(runtime.editor.isEditable, false, 'nothing to edit meanwhile');

  const unknownAttribute = await call('setContent', {
    format: 'json',
    content: doc({ ...paragraph('x'), attrs: { blockId: 'b1' } }, { type: 'image', attrs: { src: 'a.png', caption: 'c' } }),
  });
  assert.equal(unknownAttribute.reason, 'unknownAttributes');
  assert.deepEqual(unknownAttribute.attributes, ['image.caption', 'paragraph.blockId']);

  const newer = await call('setContent', { format: 'json', content: doc(paragraph('x')), schemaVersion: 3 });
  assert.equal(newer.reason, 'newerSchema');
  assert.equal(newer.documentVersion, 3);
  assert.equal(newer.bundleVersion, 2);
});

test('converts HTML through the schema, as the web editor does', async () => {
  assert.deepEqual(await call('setContent', { format: 'html', content: '<div style="border: 1px solid">Box</div><p onclick="x()">Hi</p>' }), { status: 'ok' });
  assert.equal((await call('getContent')).html, '<p>Box</p><p>Hi</p>');
});

test('runs the app\'s normalizeContent on every document', async () => {
  await call('setContent', { format: 'json', content: doc({ type: 'heading', attrs: { level: 1 }, content: [{ type: 'text', text: 'T' }] }) });
  assert.equal((await call('getContent')).html, '<h2>T</h2>');
  await call('setContent', { format: 'html', content: '<h1>H</h1>' });
  assert.equal((await call('getContent')).html, '<h2>H</h2>');
});

test('returns what keeps the document from being saved', async () => {
  await call('setContent', { format: 'json', content: doc(paragraph('x')) });
  saveProblems = [{ code: 'uploading', count: 1 }];
  assert.deepEqual((await call('getContent')).errors, [{ code: 'uploading', count: 1 }]);
  saveProblems = 'one problem';
  assert.deepEqual((await call('getContent')).errors, ['one problem']);
  saveProblems = [];
});

test('switches editing off and on', async () => {
  await call('setContent', { format: 'json', content: doc(paragraph('x')), editable: false });
  assert.equal(runtime.editor.isEditable, false);
  await call('setEditable', { editable: true });
  assert.equal(runtime.editor.isEditable, true);
});

test('a tap on a link does not follow it', async () => {
  await call('setContent', { format: 'html', content: '<p><a href="https://example.com">link</a></p>' });
  const click = new window.MouseEvent('click', { bubbles: true, cancelable: true });
  content().querySelector('a').dispatchEvent(click);
  assert.ok(click.defaultPrevented);
  assert.equal(events('linkTap').length, 0, 'the editor reports no taps');
});

test('the compatibility check names everything at once', () => {
  return import('../src/compatibility.js').then(({ incompatibility }) => {
    const schema = runtime.editor.schema;
    assert.equal(incompatibility(doc(paragraph('fine')), schema), null);
    assert.equal(incompatibility(doc(paragraph('fine')), schema, { documentVersion: 1, bundleVersion: null }), null,
      'versions count only when both are known');
  });
});
