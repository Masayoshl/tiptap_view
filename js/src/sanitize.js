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

/** Cleans [html] for showing in the view. Keeps data-* attributes, styles, details, tables and embeds. */
export function sanitize(html, window = globalThis.window) {
  return purifier(window).sanitize(html, {
    ADD_TAGS: ['iframe', 'details', 'summary'],
    ADD_ATTR: ['allow', 'allowfullscreen', 'frameborder', 'open', 'colspan', 'rowspan', 'colwidth', 'target'],
    FORBID_TAGS: ['script', 'style', 'form', 'button', 'object', 'embed', 'base', 'meta', 'link'],
  });
}
