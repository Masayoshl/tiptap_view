import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

// The runtime lives in a browser page; jsdom stands in for it, with the host page's markup.
const dom = new JSDOM('<!doctype html><html><body><div id="tv-root"><div id="tv-content"></div></div></body></html>', {
  url: 'https://tiptap-view.local/',
});
const { window } = dom;
for (const key of ['window', 'document', 'Element', 'HTMLElement', 'Node', 'DOMParser', 'CustomEvent', 'getComputedStyle']) {
  globalThis[key] = key === 'window' ? window : window[key];
}
window.__tiptapViewConfig = { token: 'secret' };

const messages = [];
window.TiptapViewBridge = { postMessage: text => messages.push(JSON.parse(text)) };

let runtime;
let mod;
before(async () => {
  mod = await import('../src/index.js');
  runtime = mod.createRuntime({
    name: 'test',
    extensions: mod.defaultExtensions(),
    viewHooks: mod.defaultViewHooks(),
    schemaVersion: 7,
    // As embedify's timestamps render <button data-video-time>; script must be refused.
    sanitize: { addTags: ['button', 'script'], addAttributes: ['aria-pressed', 'onclick'] },
  });
});

const content = () => window.document.getElementById('tv-content');
const events = name => messages.filter(message => message.type === 'event' && message.event === name);

async function call(method, params) {
  const id = `${method}-${messages.length}`;
  runtime.receive({ id, method, params });
  await new Promise(resolve => setTimeout(resolve, 0));
  const response = messages.find(message => message.type === 'response' && message.id === id);
  assert.ok(response, `no response to ${method}`);
  if (response.error) throw new Error(response.error);
  return response.result;
}

test('announces itself with the protocol, schema and extensions', () => {
  const [ready] = events('ready');
  assert.equal(ready.token, 'secret');
  assert.equal(ready.payload.protocol, mod.PROTOCOL_VERSION);
  assert.equal(ready.payload.bundle, 'test');
  assert.equal(ready.payload.schemaVersion, 7);
  assert.equal(ready.payload.mode, 'view');
  assert.deepEqual(ready.payload.modes, ['view', 'editor']);
  assert.ok(ready.payload.extensions.includes('starterKit'));
});

test('shows HTML without scripts, handlers or javascript: links', async () => {
  await call('setContent', {
    format: 'html',
    content: '<p onclick="steal()">Hi <a href="javascript:steal()">x</a><script>steal()</script></p><img src="x.png" onerror="steal()">',
  });
  const html = content().innerHTML;
  assert.ok(!/script|onclick|onerror|javascript:/i.test(html), html);
  assert.match(html, /<p>Hi /);
});

test('keeps data attributes, styles, details and tables', async () => {
  await call('setContent', {
    format: 'html',
    content: '<details data-type="collapsible" open><summary>Title</summary><p style="color: red">Body</p></details>' +
      '<p><a href="/space/page" data-page-id="12">Page</a></p><table><tbody><tr><td>A</td></tr></tbody></table>',
  });
  const root = content();
  assert.equal(root.querySelector('details').getAttribute('data-type'), 'collapsible');
  assert.equal(root.querySelector('p[style]').getAttribute('style'), 'color: red');
  assert.equal(root.querySelector('a').getAttribute('data-page-id'), '12');
  assert.ok(root.querySelector('.tv-table-scroll > table'), 'tables get a sideways scroll box');
});

test('turns YouTube iframes into previews and plays one at a time', async () => {
  const frame = id => `<iframe width="640" height="480" src="https://www.youtube.com/embed/${id}?rel=1"></iframe>`;
  await call('setContent', { format: 'html', content: frame('aaaaaaaaaaa') + frame('bbbbbbbbbbb') });
  const root = content();
  assert.equal(root.querySelectorAll('iframe').length, 0);
  const [first, second] = root.querySelectorAll('.tv-embed--youtube');
  assert.equal(first.style.aspectRatio, '640 / 480');
  assert.match(first.querySelector('img').getAttribute('src'), /vi\/aaaaaaaaaaa\/hqdefault/);

  first.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  assert.match(root.querySelector('iframe').getAttribute('src'), /aaaaaaaaaaa\?rel=1&autoplay=1&playsinline=1/);

  second.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  const frames = root.querySelectorAll('iframe');
  assert.equal(frames.length, 1, 'starting a video stops the other');
  assert.match(frames[0].getAttribute('src'), /bbbbbbbbbbb/);
  assert.equal(events('embedActivate').length, 2);
});

test('drops iframes that are not https', async () => {
  await call('setContent', { format: 'html', content: '<iframe src="http://example.com/x"></iframe><p>ok</p>' });
  assert.equal(content().querySelectorAll('iframe').length, 0);
});

test('reports link taps with their attributes and does not navigate', async () => {
  await call('setContent', { format: 'html', content: '<p><a href="/space/page" data-page-id="12">Page</a></p>' });
  const link = content().querySelector('a');
  const click = new window.MouseEvent('click', { bubbles: true, cancelable: true });
  link.dispatchEvent(click);
  assert.ok(click.defaultPrevented);
  const tap = events('linkTap').at(-1).payload;
  assert.equal(tap.href, '/space/page');
  assert.equal(tap.attributes['data-page-id'], '12');
});

test('reports image taps with the image index and rect, and hides an image on request', async () => {
  await call('setContent', {
    format: 'html',
    content: '<iframe src="https://www.youtube.com/embed/aaaaaaaaaaa"></iframe><p><img src="a.png"></p><p><img src="b.png" alt="B"></p>',
  });
  const second = content().querySelectorAll('p img')[1];
  second.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  const tap = events('imageTap').at(-1).payload;
  assert.equal(tap.src, 'b.png');
  assert.equal(tap.index, 1, 'the video poster does not count as an image');
  assert.deepEqual(Object.keys(tap.rect), ['left', 'top', 'width', 'height']);

  assert.equal(await call('setImageHidden', { index: 1, hidden: true }), true);
  assert.equal(second.style.visibility, 'hidden');
  await call('setImageHidden', { index: 1, hidden: false });
  assert.equal(second.style.visibility, '');
  assert.equal(await call('setImageHidden', { index: 9, hidden: true }), false);
});

test('renders JSON with the schema and converts HTML to JSON and back', async () => {
  const json = await call('htmlToJson', { html: '<h2>Title</h2><p>Some <strong>bold</strong> text</p><ul><li><p>one</p></li></ul>' });
  assert.equal(json.type, 'doc');
  assert.deepEqual(json.content.map(node => node.type), ['heading', 'paragraph', 'bulletList']);

  await call('setContent', { format: 'json', content: json });
  assert.match(content().innerHTML, /<h2>Title<\/h2><p>Some <strong>bold<\/strong> text<\/p>/);

  const html = await call('jsonToHtml', { json });
  assert.equal(await call('jsonToHtml', { json: await call('htmlToJson', { html }) }), html, 'html → json → html is stable');
});

test('answers an unknown method with an error, not silence', async () => {
  await assert.rejects(call('nope', {}), /Unknown method: nope/);
});

test('applies only --tv-* theme variables', async () => {
  await call('setTheme', { '--tv-color-text': '#fff', color: 'red', brightness: 'dark' });
  const root = window.document.documentElement;
  assert.equal(root.style.getPropertyValue('--tv-color-text'), '#fff');
  assert.equal(root.style.getPropertyValue('color'), '');
  assert.equal(root.dataset.brightness, 'dark');
});

test('frames other than YouTube load lazily in a box that keeps their aspect ratio', async () => {
  await call('setContent', { format: 'html', content: '<iframe width="400" height="300" src="https://player.example/x"></iframe>' });
  const box = content().querySelector('.tv-embed--frame');
  assert.ok(box, 'the frame gets a box');
  assert.equal(box.style.aspectRatio, '400 / 300');
  assert.equal(box.querySelector('iframe').getAttribute('loading'), 'lazy');
});

test('view hooks prepare content and take taps before links do; a failing hook is reported', async () => {
  const seen = [];
  runtime.view.use({
    name: 'badge',
    prepare(root, { document }) {
      for (const link of Array.from(root.querySelectorAll('a[data-badge]'))) {
        const badge = document.createElement('img');
        badge.setAttribute('src', 'badge.png');
        badge.setAttribute('data-tv-decoration', '');
        link.append(badge);
      }
    },
    click(target, _event, { emit }) {
      if (!target.closest('a[data-badge]')) return false;
      seen.push(target.tagName);
      emit('badgeTap', {});
      return true;
    },
  });
  runtime.view.use({ name: 'broken', prepare() { throw new Error('boom'); } });

  await call('setContent', { format: 'html', content: '<p><a href="/x" data-badge="1">x</a><img src="a.png"></p>' });
  assert.ok(content().querySelector('a img[data-tv-decoration]'));
  const error = events('error').at(-1).payload;
  assert.match(error.message, /boom/);
  assert.match(error.context, /broken/);

  const links = events('linkTap').length;
  const click = new window.MouseEvent('click', { bubbles: true, cancelable: true });
  content().querySelector('a').dispatchEvent(click);
  assert.ok(click.defaultPrevented);
  assert.equal(events('badgeTap').length, 1);
  assert.equal(events('linkTap').length, links, 'the hook took the tap');

  assert.equal(await call('setImageHidden', { index: 1, hidden: true }), false, 'decorations are not images');
  assert.equal(await call('setImageHidden', { index: 0, hidden: false }), true);
});

test('asks Dart with a request and waits for its answer', async () => {
  const answer = runtime.request('pickColor', { current: 'red' });
  const sent = messages.filter(message => message.type === 'request').at(-1);
  assert.equal(sent.name, 'pickColor');
  assert.deepEqual(sent.payload, { current: 'red' });
  assert.equal(sent.token, 'secret');
  runtime.resolve({ id: 'unknown', result: 1 });
  runtime.resolve({ id: sent.id, result: 'blue' });
  assert.equal(await answer, 'blue');

  const failing = runtime.request('pickColor');
  runtime.resolve({ id: messages.filter(message => message.type === 'request').at(-1).id, error: 'No handler' });
  await assert.rejects(failing, /No handler/);
});

test('keeps what the bundle allows, and refuses what runs code', async () => {
  const refusal = events('error').find(event => event.payload.context === 'sanitize');
  assert.match(refusal.payload.message, /never allows script, onclick/);
  await call('setContent', {
    format: 'html',
    content: '<p>At <button data-video-time="42" aria-pressed="false" onclick="steal()">0:42</button></p><script>steal()</script>',
  });
  const button = content().querySelector('button');
  assert.ok(button, 'the button stays');
  assert.equal(button.getAttribute('data-video-time'), '42');
  assert.equal(button.getAttribute('aria-pressed'), 'false');
  assert.equal(button.hasAttribute('onclick'), false);
  assert.equal(content().querySelector('script'), null);
});
