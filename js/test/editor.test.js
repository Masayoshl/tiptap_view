import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

// The runtime in a host page that asks for the editor mode, as TiptapEditor builds it.
const dom = new JSDOM('<!doctype html><html><body><div id="tv-root"><div id="tv-content"></div></div></body></html>', {
  url: 'https://tiptap-view.local/',
});
const { window } = dom;
for (const key of ['window', 'document', 'Element', 'HTMLElement', 'Node', 'DOMParser', 'CustomEvent', 'getComputedStyle', 'MutationObserver', 'FileReader']) {
  globalThis[key] = key === 'window' ? window : window[key];
}
// TipTap's focus waits for a frame; jsdom has no frames of its own.
globalThis.requestAnimationFrame = window.requestAnimationFrame = callback => setTimeout(callback, 0);
// ProseMirror scrolls the caret into view and measures ranges for it; jsdom does no layout.
const noRect = () => ({ left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0, x: 0, y: 0 });
window.Range.prototype.getClientRects = () => [];
window.Range.prototype.getBoundingClientRect = noRect;
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
    embeds: mod.defaultEmbeds(),
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
  // The trailing paragraph is StarterKit's TrailingNode, added when the document opens.
  assert.equal((await call('getContent')).html, '<h2>T</h2><p></p>');
  await call('setContent', { format: 'html', content: '<h1>H</h1>' });
  assert.equal((await call('getContent')).html, '<h2>H</h2><p></p>');
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
});

test('the compatibility check names everything at once', () => {
  return import('../src/compatibility.js').then(({ incompatibility }) => {
    const schema = runtime.editor.schema;
    assert.equal(incompatibility(doc(paragraph('fine')), schema), null);
    assert.equal(incompatibility(doc(paragraph('fine')), schema, { documentVersion: 1, bundleVersion: null }), null,
      'versions count only when both are known');
  });
});

const settle = () => new Promise(resolve => setTimeout(resolve, 60));

test('runs TipTap commands by name, with arguments, and says which can run', async () => {
  await call('setContent', { format: 'json', content: doc(paragraph('Hello world')) });
  runtime.editor.commands.setTextSelection({ from: 1, to: 6 });
  assert.equal(await call('command', { name: 'toggleBold' }), true);
  assert.equal(await call('command', { name: 'setLink', args: { href: 'https://example.com' } }), true);
  assert.equal(await call('command', { name: 'toggleHeading', args: [{ level: 3 }] }), true);
  // StarterKit's TrailingNode keeps an empty paragraph after a last block that is not one.
  assert.equal((await call('getContent')).html,
    '<h3><a target="_blank" rel="noopener noreferrer nofollow" href="https://example.com"><strong>Hello</strong></a> world</h3><p></p>');

  assert.equal(await call('canRun', { name: 'undo' }), true);
  assert.equal(await call('canRun', { name: 'redo' }), false);
  await assert.rejects(call('command', { name: 'launchRocket' }), /Unknown command: launchRocket/);
  const names = await call('commands');
  assert.ok(names.includes('toggleBold') && names.includes('insertTable'), 'commands come from the extensions');
});

test('sends the toolbar state after a transaction, once per change, from the schema\'s names', async () => {
  await call('setContent', { format: 'json', content: doc({ type: 'heading', attrs: { level: 2, textAlign: 'center' }, content: [{ type: 'text', text: 'Title', marks: [{ type: 'italic' }] }] }) });
  await settle();
  const opened = events('state').at(-1).payload;
  assert.equal(opened.canUndo, false);
  assert.equal(opened.editable, true);

  runtime.editor.commands.setTextSelection({ from: 2, to: 4 });
  await settle();
  const before = events('state').length;
  const state = events('state').at(-1).payload;
  assert.deepEqual(Object.keys(state.marks), ['italic']);
  assert.deepEqual(state.nodes, [{ type: 'heading', attrs: { level: 2, textAlign: 'center' } }]);
  assert.deepEqual(state.selection, { empty: false, from: 2, to: 4, node: null });

  runtime.editor.commands.setTextSelection({ from: 2, to: 4 });
  await settle();
  assert.equal(events('state').length, before, 'the same state is not sent twice');

  await call('command', { name: 'toggleBold' });
  await settle();
  const bold = events('state').at(-1).payload;
  assert.deepEqual(Object.keys(bold.marks).sort(), ['bold', 'italic']);
  assert.equal(bold.canUndo, true);
  assert.deepEqual(await call('getState'), bold);
});

test('a link\'s attributes and a list\'s nesting are in the state', async () => {
  await call('setContent', { format: 'html', content: '<ul><li><p><a href="/x" title="X">item</a></p></li></ul>' });
  runtime.editor.commands.setTextSelection(4);
  await settle();
  const state = events('state').at(-1).payload;
  assert.equal(state.marks.link.href, '/x');
  assert.deepEqual(state.nodes.map(node => node.type), ['bulletList', 'listItem', 'paragraph']);
});

test('wide tables get a sideways-scrolling wrapper in the editor', async () => {
  assert.equal(window.document.documentElement.dataset.tvMode, 'editor');
  await call('setContent', { format: 'html', content: '<table><tbody><tr><td><p>A</p></td><td><p>B</p></td></tr></tbody></table>' });
  const wrapper = content().querySelector('.tableWrapper');
  assert.ok(wrapper, 'the table has a wrapper');
  assert.ok(wrapper.querySelector(':scope > table > colgroup'), 'with the column widths, as TipTap renders them');
  runtime.editor.commands.setTextSelection(4);
  assert.equal(await call('command', { name: 'addColumnAfter' }), true);
  assert.equal(content().querySelectorAll('.tableWrapper td').length, 3, 'the node view follows edits');
});

const html = async () => (await call('getContent')).html;
const tap = element => element.dispatchEvent(new window.MouseEvent('click', { bubbles: true, cancelable: true }));

test('an upload waits as a placeholder, outside the document, and becomes the app\'s image node', async () => {
  await call('setContent', { format: 'json', content: doc(paragraph('Hello')) });
  runtime.editor.commands.setTextSelection(6);
  await call('beginUpload', { id: 'u1', preview: 'data:image/png;base64,AAAA' });
  const box = content().querySelector('.tv-upload--pending[data-upload-id="u1"]');
  assert.ok(box, 'a placeholder shows');
  assert.equal(box.querySelector('img').getAttribute('src'), 'data:image/png;base64,AAAA');
  assert.equal(await html(), '<p>Hello</p>', 'nothing pending is in the document');
  assert.deepEqual((await call('getContent')).errors, [{ code: 'uploading', count: 1 }]);

  // The placeholder follows edits before it.
  runtime.editor.commands.insertContentAt(1, 'Oh. ');
  const errors = events('error').length;
  assert.equal(await call('finishUpload', { id: 'u1', src: 'https://cdn.example/a.png', attributes: { alt: 'A', mediaId: 'm1' } }), true);
  // The default Image is a block node, so it goes after the paragraph.
  assert.equal(await html(), '<p>Oh. Hello</p><img src="https://cdn.example/a.png" alt="A"><p></p>');
  assert.match(events('error').at(-1).payload.message, /does not declare mediaId/, 'an attribute the node lacks is reported, not lost silently');
  assert.equal(events('error').length, errors + 1);
  assert.deepEqual((await call('getContent')).errors, []);
  assert.equal(content().querySelector('.tv-upload'), null);
  assert.equal(await call('finishUpload', { id: 'u1', src: 'x' }), false, 'an upload finishes once');

  runtime.editor.commands.undo();
  assert.equal(await html(), '<p>Oh. Hello</p>', 'undo takes the image out');
});

test('a failed upload can be tried again or removed, from its placeholder', async () => {
  await call('setContent', { format: 'json', content: doc(paragraph('x')) });
  await call('beginUpload', { id: 'u2' });
  await call('failUpload', { id: 'u2', message: 'Too large' });
  const failed = content().querySelector('.tv-upload--failed');
  assert.equal(failed.title, 'Too large');
  assert.deepEqual((await call('getContent')).errors, [{ code: 'uploadFailed', count: 1 }]);

  tap(failed.querySelector('.tv-upload__retry'));
  assert.deepEqual(events('uploadRetry').at(-1).payload, { id: 'u2' });
  assert.ok(content().querySelector('.tv-upload--pending'), 'pending again, in place');

  await call('failUpload', { id: 'u2' });
  tap(content().querySelector('.tv-upload__remove'));
  assert.deepEqual(events('uploadCancel').at(-1).payload, { id: 'u2' });
  assert.equal(content().querySelector('.tv-upload'), null);
  assert.deepEqual((await call('getContent')).errors, []);
});

function pasteFile(file, htmlText = '') {
  const event = new window.Event('paste', { bubbles: true, cancelable: true });
  Object.defineProperty(event, 'clipboardData', {
    value: { files: [file], types: ['Files'], getData: type => (type === 'text/html' ? htmlText : '') },
  });
  content().querySelector('.ProseMirror').dispatchEvent(event);
  return event;
}

test('a pasted image file is uploaded through the imageUpload request, when the app handles it', async () => {
  await call('setContent', { format: 'json', content: doc(paragraph('x')) });
  const file = new window.File([new Uint8Array([1, 2, 3])], 'shot.png', { type: 'image/png' });

  const ignored = pasteFile(file);
  assert.equal(ignored.defaultPrevented, false, 'without the app\'s handler, a pasted file is not taken');
  // ProseMirror tries a paste nobody took once more, a moment later; let that pass.
  await new Promise(resolve => setTimeout(resolve, 80));

  await call('setImagePaste', { enabled: true });
  const requests = () => messages.filter(message => message.type === 'request' && message.name === 'imageUpload');
  const before = requests().length;
  assert.equal(pasteFile(file).defaultPrevented, true);
  await new Promise(resolve => setTimeout(resolve, 20));
  const sent = requests().at(-1);
  assert.equal(requests().length, before + 1);
  assert.deepEqual({ data: sent.payload.data, type: sent.payload.type, name: sent.payload.name }, { data: 'AQID', type: 'image/png', name: 'shot.png' });
  assert.ok(content().querySelector('.tv-upload--pending img[src^="data:image/png"]'), 'the pasted image previews meanwhile');

  runtime.resolve({ id: sent.id, result: { src: 'https://cdn.example/shot.png' } });
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.match(await html(), /<img src="https:\/\/cdn.example\/shot.png">/);

  pasteFile(file);
  await new Promise(resolve => setTimeout(resolve, 20));
  runtime.resolve({ id: requests().at(-1).id, error: 'offline' });
  await new Promise(resolve => setTimeout(resolve, 0));
  tap(content().querySelector('.tv-upload--failed .tv-upload__retry'));
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(requests().length, before + 3, 'a pasted image is tried again by the page itself');
  await call('setImagePaste', { enabled: false });
});

test('edits links with what the app asked for, and reports taps on them', async () => {
  await call('setContent', { format: 'json', content: doc(paragraph('See ')) });
  runtime.editor.commands.setTextSelection(5);
  assert.deepEqual(await call('getLink'), { active: false, href: null, attributes: {}, text: '', empty: true });

  assert.equal(await call('setLink', { href: '/docs', text: 'the docs', attributes: { title: 'Docs' } }), true);
  assert.equal(await html(), '<p>See <a target="_blank" rel="noopener noreferrer nofollow" href="/docs" title="Docs">the docs</a></p>');

  runtime.editor.commands.setTextSelection(8);
  const link = await call('getLink');
  assert.equal(link.active, true);
  assert.equal(link.href, '/docs');
  assert.equal(link.text, 'the docs');
  assert.equal(link.attributes.title, 'Docs');

  await assert.rejects(call('setLink', { href: '/x', attributes: { 'data-page-id': '1' } }), /does not declare data-page-id/);
  assert.equal(await call('setLink', { href: '/manual' }), true, 'inside a link, the whole link changes');
  assert.match(await html(), /href="\/manual" title="Docs">the docs<\/a>/);

  tap(content().querySelector('a'));
  const tapped = events('linkTap').at(-1).payload;
  assert.equal(tapped.href, '/manual');
  assert.equal(tapped.text, 'the docs');

  runtime.editor.commands.setTextSelection(8);
  assert.equal(await call('removeLink'), true);
  assert.equal(await html(), '<p>See the docs</p>');
});

test('turns a URL into an embed with the bundle\'s resolvers', async () => {
  await call('setContent', { format: 'json', content: doc(paragraph('x')) });
  assert.deepEqual(await call('insertEmbed', { url: 'https://www.youtube.com/watch?v=aaaaaaaaaaa' }), { inserted: true, type: 'youtube' });
  assert.match(await html(), /youtube(-nocookie)?\.com\/embed\/aaaaaaaaaaa/);
  assert.deepEqual(await call('insertEmbed', { url: 'https://example.com/page' }), { inserted: false, type: null });
});

test('an untouched document is not edited: normalizing plugins run when it opens', async () => {
  const before = events('change').length;
  // A last block that is not a paragraph: StarterKit's TrailingNode adds one after it.
  await call('setContent', { format: 'json', content: doc({ type: 'heading', attrs: { level: 2 }, content: [{ type: 'text', text: 'T' }] }) });
  const opened = await call('getContent');
  assert.equal(opened.version, 0);
  assert.equal(opened.html, '<h2>T</h2><p></p>', 'the trailing paragraph is there from the start');
  runtime.editor.commands.setTextSelection(2);
  await new Promise(resolve => setTimeout(resolve, 200));
  assert.equal((await call('getContent')).version, 0, 'a tap is not an edit');
  assert.equal(runtime.editor.can().undo(), false);
  assert.equal(events('change').length, before);
});
