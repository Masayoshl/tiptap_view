import { sanitize } from './sanitize.js';
import { prepareFrames } from './embeds.js';

/**
 * The read-only view: the document is HTML in `#tv-content`, sanitized, and this mode changes that DOM
 * freely (table boxes, lazy images, frame boxes, whatever view hooks do). It also turns taps on links and
 * images into events, since nothing in the view navigates by itself.
 *
 * A view hook adds behavior for content the core knows nothing about, embeds for one:
 *
 *   {
 *     name: 'youtube',
 *     prepare(root, context) {},           // after each render, before frames get their boxes
 *     click(target, event, context) {},    // return true when the tap was the hook's: nothing else sees it
 *   }
 *
 * `context` has `emit`, `reportHeight` and `document`. Images a hook adds that are not the document's own
 * (posters, icons) carry `data-tv-decoration`: taps on them and `setImageHidden` indexes ignore them.
 */
export function createViewMode(core, { hooks: initialHooks = [] } = {}) {
  const { content, emit, reportHeight, htmlFromJson, reportError } = core;
  const hooks = [];
  const context = { emit, reportHeight, document };

  function use(hook) {
    if (!hook || typeof hook !== 'object') throw new Error('A view hook is an object with prepare and/or click');
    hooks.push(hook);
  }
  for (const hook of initialHooks) use(hook);

  function runHooks(phase, ...args) {
    for (const hook of hooks) {
      if (typeof hook[phase] !== 'function') continue;
      try {
        if (hook[phase](...args, context) === true) return true;
      } catch (error) {
        reportError(error, `view hook ${hook.name || '?'} (${phase})`);
      }
    }
    return false;
  }

  // Content --------------------------------------------------------------------------------------------

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
    runHooks('prepare', content);
    prepareFrames(content);
    reportHeight();
  }

  function images() {
    return Array.from(content.querySelectorAll('img:not([data-tv-decoration])'));
  }

  // Taps -----------------------------------------------------------------------------------------------

  function attributes(element) {
    const result = {};
    for (const attribute of Array.from(element.attributes)) result[attribute.name] = attribute.value;
    return result;
  }

  document.addEventListener('click', event => {
    const target = event.target instanceof Element ? event.target : null;
    if (!target || !content.contains(target)) return;

    if (runHooks('click', target, event)) {
      event.preventDefault();
      return;
    }

    const link = target.closest('a');
    if (link) {
      event.preventDefault();
      if (!link.hasAttribute('href')) return;
      emit('linkTap', { href: link.getAttribute('href'), text: link.textContent || '', attributes: attributes(link) });
      return;
    }

    if (target.tagName === 'IMG' && !target.hasAttribute('data-tv-decoration')) {
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

  // Collapsible blocks change the height when they open or close.
  document.addEventListener('toggle', reportHeight, true);

  return {
    view: { use },
    methods: {
      setContent({ format, content: value, sanitize: clean = true }) {
        // JSON is rendered by the schema, so it is clean by construction; sanitizing again changes nothing.
        const html = format === 'json' ? htmlFromJson(value) : String(value ?? '');
        render(html, { sanitized: clean });
      },
      getHtml: () => content.innerHTML,
      // Hides an image in place while the app shows a copy of it elsewhere, a full-screen viewer for one.
      setImageHidden({ index, hidden }) {
        const image = images()[index];
        if (!image) return false;
        image.style.visibility = hidden ? 'hidden' : '';
        return true;
      },
    },
  };
}
