import { isValidYoutubeUrl } from '@tiptap/extension-youtube';
import { aspectRatio } from './embeds.js';

// A view hook for YouTube embeds. Players are heavy: every live iframe is a page of its own. The document
// shows a still preview instead, and only the one the reader taps becomes a live player; starting another
// one stops it. Each start sends `embedActivate` with the embed's URL.

const YOUTUBE_EMBED = /^(?:https?:)?\/\/(?:www\.)?(?:youtube\.com|youtube-nocookie\.com)\/embed\/([\w-]{6,})/i;

export function youtubeId(src) {
  const match = YOUTUBE_EMBED.exec(src || '');
  return match ? match[1] : null;
}

/** The player URL for a tapped preview: the stored embed URL, set to start at once and play inline. */
export function playerUrl(src) {
  const url = new URL(src, 'https://www.youtube.com');
  url.searchParams.set('autoplay', '1');
  url.searchParams.set('playsinline', '1');
  return url.toString();
}

function preview(document, src, ratio) {
  const box = document.createElement('div');
  box.className = 'tv-embed tv-embed--youtube';
  box.dataset.src = src;
  box.style.aspectRatio = ratio;
  box.setAttribute('role', 'button');
  box.setAttribute('aria-label', 'Play video');
  box.innerHTML =
    `<img class="tv-embed__poster" data-tv-decoration alt="" loading="lazy" src="https://img.youtube.com/vi/${youtubeId(src)}/hqdefault.jpg">` +
    '<span class="tv-embed__play" aria-hidden="true"></span>';
  return box;
}

/** Turns a preview into a live player and the previously live one back into a preview. */
function activate(box) {
  const document = box.ownerDocument;
  for (const live of Array.from(document.querySelectorAll('.tv-embed--youtube.tv-embed--live'))) {
    if (live !== box) live.replaceWith(preview(document, live.dataset.src, live.style.aspectRatio));
  }

  const iframe = document.createElement('iframe');
  iframe.setAttribute('src', playerUrl(box.dataset.src));
  iframe.setAttribute('allow', 'autoplay; encrypted-media; picture-in-picture; fullscreen');
  iframe.setAttribute('allowfullscreen', 'true');
  iframe.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
  // As sanitized frames: the player may run and go fullscreen, never navigate this page.
  iframe.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-presentation allow-popups');
  box.classList.add('tv-embed--live');
  box.removeAttribute('role');
  box.replaceChildren(iframe);
}

export function youtubePreview() {
  return {
    name: 'youtube',
    prepare(root) {
      for (const iframe of Array.from(root.querySelectorAll('iframe'))) {
        const src = iframe.getAttribute('src');
        if (youtubeId(src)) iframe.replaceWith(preview(root.ownerDocument, src, aspectRatio(iframe)));
      }
    },
    click(target, _event, { emit }) {
      const box = target.closest('.tv-embed--youtube:not(.tv-embed--live)');
      if (!box) return false;
      activate(box);
      emit('embedActivate', { src: box.dataset.src || '' });
      return true;
    },
  };
}

/** An embed resolver for the editor: a YouTube URL becomes the Youtube extension's node, when the schema has it. */
export function youtubeEmbed() {
  return (url, { schema }) => (schema.nodes.youtube && isValidYoutubeUrl(url) ? { type: 'youtube', attrs: { src: url } } : null);
}
