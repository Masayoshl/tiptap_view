import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

// A host page that asks for a mode the runtime lacks: the runtime says so instead of half starting.
const dom = new JSDOM('<!doctype html><html><body><div id="tv-root"><div id="tv-content"></div></div></body></html>', {
  url: 'https://tiptap-view.local/',
});
const { window } = dom;
for (const key of ['window', 'document', 'Element', 'HTMLElement', 'Node', 'DOMParser', 'CustomEvent', 'getComputedStyle']) {
  globalThis[key] = key === 'window' ? window : window[key];
}
window.__tiptapViewConfig = { token: 'secret', mode: 'slides' };
const messages = [];
window.TiptapViewBridge = { postMessage: text => messages.push(JSON.parse(text)) };

test('reports a mode it lacks and announces no mode', async () => {
  const mod = await import('../src/index.js');
  const runtime = mod.createRuntime({ name: 'test', extensions: mod.defaultExtensions() });
  const error = messages.find(message => message.event === 'error');
  assert.equal(error.payload.context, 'mode');
  assert.match(error.payload.message, /no "slides" mode/);
  const ready = messages.find(message => message.event === 'ready');
  assert.equal(ready.payload.mode, null);
  assert.equal(runtime.mode, null);

  runtime.view.use({ prepare() {} });
  runtime.receive({ id: '1', method: 'setContent', params: { format: 'html', content: '<p>x</p>' } });
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.match(messages.find(message => message.id === '1').error, /Unknown method: setContent/);
  runtime.receive({ id: '2', method: 'htmlToJson', params: { html: '<p>x</p>' } });
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(messages.find(message => message.id === '2').result.type, 'doc', 'schema methods work in any mode');
});
