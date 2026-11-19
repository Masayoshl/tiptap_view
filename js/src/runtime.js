import { generateHTML, generateJSON, getSchema } from '@tiptap/core';
import { createViewMode } from './view-mode.js';
import { createEditorMode } from './editor-mode.js';

// Bumped whenever a message changes shape. Dart refuses a runtime that speaks another version.
// 2: requests from the page to Dart, the `mode` in `ready`.
export const PROTOCOL_VERSION = 2;
export const RUNTIME_VERSION = typeof __RUNTIME_VERSION__ === 'string' ? __RUNTIME_VERSION__ : 'dev';
export const TIPTAP_VERSION = typeof __TIPTAP_VERSION__ === 'string' ? __TIPTAP_VERSION__ : 'dev';

const CHANNEL = 'TiptapViewBridge';

// The modes this runtime can start in. The host page's config says which one: TiptapView starts `view`,
// TiptapEditor starts `editor`.
const MODES = { view: createViewMode, editor: createEditorMode };

/**
 * Starts the runtime in the host page. A bundle calls it once, with its extensions:
 *
 *   createRuntime({ extensions: [...defaultExtensions(), MyNode], viewHooks: defaultViewHooks(), schemaVersion: 3 });
 *
 * The extensions define the document schema. The core here is what every mode shares: the bridge to Dart,
 * methods and events, requests, the theme, height reports and errors. A mode (see view-mode.js) owns the
 * document's DOM and adds its own methods.
 *
 * [viewHooks] add behavior to the view mode only (see view-mode.js): previews for embeds, for one.
 * [editorExtensions], [normalizeContent], [validateForSave] and [embeds] are for the editor mode (see
 * editor-mode.js).
 */
export function createRuntime({
  extensions,
  schemaVersion = null,
  name = 'custom',
  viewHooks = [],
  editorExtensions = [],
  normalizeContent = null,
  validateForSave = null,
  embeds = [],
} = {}) {
  if (!Array.isArray(extensions) || !extensions.length) throw new Error('createRuntime needs extensions');
  const config = window.__tiptapViewConfig || {};
  const token = config.token || '';
  const modeName = config.mode || 'view';
  const handlers = new Map();
  const requests = new Map();
  let requestId = 0;
  let schema = null;
  const schemaFor = () => (schema ??= getSchema(extensions));

  function post(message) {
    const channel = window[CHANNEL];
    const text = JSON.stringify({ ...message, token });
    if (channel && typeof channel.postMessage === 'function') channel.postMessage(text);
    else window.dispatchEvent(new CustomEvent('tiptap-view-message', { detail: JSON.parse(text) }));
  }

  function emit(event, payload = {}) {
    post({ type: 'event', event, payload });
  }

  /** Asks Dart something and waits for the answer: an extension's request handler gives it. */
  function request(requestName, payload = {}) {
    const id = `r${++requestId}`;
    return new Promise((resolve, reject) => {
      requests.set(id, { resolve, reject });
      post({ type: 'request', id, name: requestName, payload });
    });
  }

  /** Entry point for Dart's answers to [request]: `window.tiptapView.resolve({ id, result | error })`. */
  function resolve(message) {
    const { id, result, error } = message || {};
    const pending = requests.get(id);
    if (!pending) return;
    requests.delete(id);
    if (typeof error === 'string') pending.reject(new Error(error));
    else pending.resolve(result === undefined ? null : result);
  }

  function reportError(error, context) {
    emit('error', { message: String((error && error.message) || error), context, stack: error && error.stack });
  }

  // Height ---------------------------------------------------------------------------------------------

  const root = document.getElementById('tv-root');
  const content = document.getElementById('tv-content');

  let lastHeight = -1;
  function reportHeight() {
    const height = Math.ceil(root.getBoundingClientRect().height);
    if (height === lastHeight) return;
    lastHeight = height;
    emit('height', { height });
  }
  if (typeof ResizeObserver === 'function') new ResizeObserver(reportHeight).observe(root);
  window.addEventListener('load', reportHeight);

  // Theme ----------------------------------------------------------------------------------------------

  function setTheme(variables) {
    const style = document.documentElement.style;
    for (const [key, value] of Object.entries(variables || {})) {
      if (!key.startsWith('--tv-')) continue;
      if (value == null) style.removeProperty(key);
      else style.setProperty(key, String(value));
    }
    if (variables && typeof variables.brightness === 'string') document.documentElement.dataset.brightness = variables.brightness;
    reportHeight();
  }

  // Schema ---------------------------------------------------------------------------------------------

  const htmlFromJson = json => generateHTML(typeof json === 'string' ? JSON.parse(json) : json, extensions);

  // Mode -----------------------------------------------------------------------------------------------

  const core = { extensions, content, emit, request, reportError, reportHeight, htmlFromJson, schemaFor, schemaVersion };
  const options = { hooks: viewHooks, editorExtensions, normalizeContent, validateForSave, embeds };
  const start = MODES[modeName];
  // Styles that differ by mode (tables in the editor, for one) hang off this attribute.
  if (start) document.documentElement.dataset.tvMode = modeName;
  let mode = null;
  if (start) {
    mode = start(core, options);
  } else {
    reportError(new Error(`This runtime has no "${modeName}" mode; it has ${Object.keys(MODES).join(', ')}`), 'mode');
  }

  // Methods called from Dart ---------------------------------------------------------------------------

  const methods = {
    setTheme,
    htmlToJson: ({ html }) => generateJSON(String(html ?? ''), extensions),
    jsonToHtml: ({ json }) => htmlFromJson(json),
    nodeTypes: () => Object.keys(schemaFor().nodes),
    ...(mode ? mode.methods : {}),
  };

  /** Entry point for Dart: `window.tiptapView.receive({ id, method, params })`. */
  function receive(message) {
    const { id, method, params } = message || {};
    try {
      const handler = methods[method] || handlers.get(method);
      if (!handler) throw new Error(`Unknown method: ${method}`);
      const result = handler(params || {});
      Promise.resolve(result).then(
        value => post({ type: 'response', id, result: value === undefined ? null : value }),
        error => post({ type: 'response', id, error: String((error && error.message) || error) }),
      );
    } catch (error) {
      post({ type: 'response', id, error: String((error && error.message) || error) });
    }
  }

  window.addEventListener('error', event => reportError(event.error || event.message, 'window'));
  window.addEventListener('unhandledrejection', event => reportError(event.reason, 'promise'));

  const runtime = {
    receive,
    resolve,
    emit,
    request,
    /** The started mode's name, or null when the host page asked for a mode this runtime lacks. */
    mode: mode ? modeName : null,
    /** The view mode's API (`use` a view hook); its calls do nothing in other modes. */
    view: (mode && mode.view) || { use() {} },
    /** The TipTap `Editor` in the editor mode, once a document is open; null otherwise. */
    get editor() {
      return mode && mode.current ? mode.current() : null;
    },
    /** Lets a bundle add its own methods, callable from Dart with `controller.call(name, params)`. */
    register(method, handler) {
      if (methods[method]) throw new Error(`${method} is a built-in method`);
      handlers.set(method, handler);
    },
  };
  window.tiptapView = runtime;

  emit('ready', {
    protocol: PROTOCOL_VERSION,
    runtimeVersion: RUNTIME_VERSION,
    tiptapVersion: TIPTAP_VERSION,
    bundle: name,
    schemaVersion,
    mode: runtime.mode,
    modes: Object.keys(MODES),
    extensions: extensions.map(extension => extension.name),
  });

  return runtime;
}
