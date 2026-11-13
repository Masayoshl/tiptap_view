import { generateHTML, generateJSON, getSchema } from '@tiptap/core';
import { sanitize } from './sanitize.js';
import { activateEmbed, prepareEmbeds } from './embeds.js';

// Bumped whenever a message changes shape. Dart refuses a runtime that speaks another version.
export const PROTOCOL_VERSION = 1;
export const RUNTIME_VERSION = typeof __RUNTIME_VERSION__ === 'string' ? __RUNTIME_VERSION__ : 'dev';
export const TIPTAP_VERSION = typeof __TIPTAP_VERSION__ === 'string' ? __TIPTAP_VERSION__ : 'dev';

const CHANNEL = 'TiptapViewBridge';

/**
 * Starts the runtime in the host page. A bundle calls it once, with its extensions:
 *
 *   createRuntime({ extensions: [...defaultExtensions(), MyNode], schemaVersion: 3 });
 *
 * The extensions define the document schema: JSON content is rendered with them, and HTML can be
 * converted to JSON with them. HTML content itself is shown as it is, after sanitizing, the way a web
 * reader shows a published page.
 */
export function createRuntime({ extensions, schemaVersion = null, name = 'custom' } = {}) {
  if (!Array.isArray(extensions) || !extensions.length) throw new Error('createRuntime needs extensions');
  const config = window.__tiptapViewConfig || {};
  const token = config.token || '';
  const handlers = new Map();
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

  function reportError(error, context) {
    emit('error', { message: String((error && error.message) || error), context, stack: error && error.stack });
  }

  // Content --------------------------------------------------------------------------------------------

  const root = document.getElementById('tv-root');
  const content = document.getElementById('tv-content');

  function render(html, { sanitized = true } = {}) {
    content.innerHTML = sanitized ? sanitize(html, window) : html;
    for (const image of Array.from(content.querySelectorAll('img'))) {
      if (!image.hasAttribute('loading')) image.setAttribute('loading', 'lazy');
      image.addEventListener('load', reportHeight, { once: true });
    }
    // Wide tables scroll sideways inside their own box, not the page.
    for (const table of Array.from(content.querySelectorAll('table'))) {
      if (table.parentElement && table.parentElement.classList.contains('tv-table-scroll')) continue;
      const box = document.createElement('div');
      box.className = 'tv-table-scroll';
      table.replaceWith(box);
      box.appendChild(table);
    }
    const embeds = prepareEmbeds(content);
    reportHeight();
    return { embeds };
  }

  function htmlFromJson(json) {
    return generateHTML(json, extensions);
  }

  // Height ---------------------------------------------------------------------------------------------

  let lastHeight = -1;
  function reportHeight() {
    const height = Math.ceil(root.getBoundingClientRect().height);
    if (height === lastHeight) return;
    lastHeight = height;
    emit('height', { height });
  }
  if (typeof ResizeObserver === 'function') new ResizeObserver(reportHeight).observe(root);
  window.addEventListener('load', reportHeight);

  // Taps -----------------------------------------------------------------------------------------------

  function attributes(element) {
    const result = {};
    for (const attribute of Array.from(element.attributes)) result[attribute.name] = attribute.value;
    return result;
  }

  document.addEventListener('click', event => {
    const target = event.target instanceof Element ? event.target : null;
    if (!target) return;

    const embed = target.closest('.tv-embed--youtube:not(.tv-embed--live)');
    if (embed) {
      event.preventDefault();
      activateEmbed(embed);
      emit('embedActivate', { src: embed.dataset.src || '' });
      return;
    }

    const link = target.closest('a');
    if (link && content.contains(link)) {
      event.preventDefault();
      if (!link.hasAttribute('href')) return;
      emit('linkTap', { href: link.getAttribute('href'), text: link.textContent || '', attributes: attributes(link) });
      return;
    }

    if (target.tagName === 'IMG' && content.contains(target)) {
      // Where the image is, so the app can fly it into a full-screen viewer; the page never scrolls inside
      // the view, so the rect is relative to the view's top left.
      const box = target.getBoundingClientRect();
      emit('imageTap', {
        src: target.getAttribute('src') || '',
        alt: target.getAttribute('alt') || '',
        attributes: attributes(target),
        index: images().indexOf(target),
        rect: { left: box.left, top: box.top, width: box.width, height: box.height },
      });
    }
  }, true);

  function images() {
    return Array.from(content.querySelectorAll('img:not(.tv-embed__poster)'));
  }

  // Collapsible blocks change the height when they open or close.
  document.addEventListener('toggle', reportHeight, true);

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

  // Methods called from Dart ---------------------------------------------------------------------------

  const methods = {
    setContent({ format, content: value, sanitize: clean = true }) {
      if (format === 'json') {
        // Rendered by the schema, so it is clean by construction; sanitizing again changes nothing.
        return render(htmlFromJson(typeof value === 'string' ? JSON.parse(value) : value), { sanitized: clean });
      }
      return render(String(value ?? ''), { sanitized: clean });
    },
    setTheme,
    getHtml: () => content.innerHTML,
    htmlToJson: ({ html }) => generateJSON(String(html ?? ''), extensions),
    jsonToHtml: ({ json }) => htmlFromJson(typeof json === 'string' ? JSON.parse(json) : json),
    nodeTypes: () => Object.keys(schemaFor().nodes),
    // Hides an image in place while the app shows a copy of it elsewhere, a full-screen viewer for one.
    setImageHidden({ index, hidden }) {
      const image = images()[index];
      if (!image) return false;
      image.style.visibility = hidden ? 'hidden' : '';
      return true;
    },
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
    emit,
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
    extensions: extensions.map(extension => extension.name),
  });

  return runtime;
}
