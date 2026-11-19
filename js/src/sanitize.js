import DOMPurify from 'dompurify';

// The document runs next to the bridge, so markup must not run code of its own: no scripts, no inline
// handlers, no javascript: URLs. Embeds stay, but only over https and without access to this page.
let configured = null;

function purifier(window) {
  if (configured && configured.window === window) return configured.purify;
  const purify = DOMPurify(window);
  purify.addHook('uponSanitizeElement', (node, data) => {
    if (data.tagName !== 'iframe') return;
    const src = node.getAttribute('src') || '';
    if (!/^https:\/\//i.test(src)) node.remove();
  });
  purify.addHook('afterSanitizeAttributes', node => {
    if (node.tagName === 'IFRAME') node.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-presentation allow-popups');
    // Task lists render checkboxes; nothing else in a read-only document takes input.
    if (node.tagName === 'INPUT') {
      if ((node.getAttribute('type') || '').toLowerCase() !== 'checkbox') node.remove();
      else node.setAttribute('disabled', '');
    }
  });
  configured = { window, purify };
  return purify;
}

const FORBIDDEN = ['script', 'style', 'form', 'button', 'object', 'embed', 'base', 'meta', 'link'];

// What no bundle may let through: elements that run code, load code or change how the page loads. Event
// handler attributes and javascript: URLs are always removed by DOMPurify itself.
const NEVER = new Set(['script', 'style', 'object', 'embed', 'base', 'meta', 'link', 'form', 'frame', 'frameset', 'template', 'svg', 'math']);

/**
 * Checks a bundle's allowances (`createRuntime({ sanitize })`): tags and attributes its own nodes render
 * that the view would otherwise remove, a timestamp `button` for one. Returns the usable part, and what
 * was refused as unsafe.
 */
export function sanitizeAllowances({ addTags = [], addAttributes = [] } = {}) {
  const tags = addTags.map(tag => String(tag).toLowerCase());
  const attributes = addAttributes.map(name => String(name).toLowerCase());
  return {
    addTags: tags.filter(tag => !NEVER.has(tag)),
    addAttributes: attributes.filter(name => !name.startsWith('on')),
    refused: [...tags.filter(tag => NEVER.has(tag)), ...attributes.filter(name => name.startsWith('on'))],
  };
}

/**
 * Cleans [html] for showing in the view. Keeps data-* attributes, styles, details, tables and embeds, and
 * what [allowances] add (see [sanitizeAllowances]).
 */
export function sanitize(html, window = globalThis.window, { addTags = [], addAttributes = [] } = {}) {
  return purifier(window).sanitize(html, {
    ADD_TAGS: ['iframe', 'details', 'summary', ...addTags],
    ADD_ATTR: ['allow', 'allowfullscreen', 'frameborder', 'open', 'colspan', 'rowspan', 'colwidth', 'target', ...addAttributes],
    FORBID_TAGS: FORBIDDEN.filter(tag => !addTags.includes(tag)),
  });
}
