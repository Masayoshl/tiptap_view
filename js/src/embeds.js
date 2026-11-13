// Embedded players are heavy: every live iframe is a page of its own. A document shows a still preview
// instead, and only the embed the reader taps becomes a live player; starting another one stops it.

const YOUTUBE_EMBED = /^(?:https?:)?\/\/(?:www\.)?(?:youtube\.com|youtube-nocookie\.com)\/embed\/([\w-]{6,})/i;

export function youtubeId(src) {
  const match = YOUTUBE_EMBED.exec(src || '');
  return match ? match[1] : null;
}

function aspectRatio(element) {
  const width = Number(element.getAttribute('width'));
  const height = Number(element.getAttribute('height'));
  return width > 0 && height > 0 ? `${width} / ${height}` : '16 / 9';
}

/** The player URL for a tapped preview: the stored embed URL, set to start at once and play inline. */
export function playerUrl(src) {
  const url = new URL(src, 'https://www.youtube.com');
  url.searchParams.set('autoplay', '1');
  url.searchParams.set('playsinline', '1');
  return url.toString();
}

function preview(iframe, id) {
  const box = iframe.ownerDocument.createElement('div');
  box.className = 'tv-embed tv-embed--youtube';
  box.dataset.src = iframe.getAttribute('src');
  box.style.aspectRatio = aspectRatio(iframe);
  box.setAttribute('role', 'button');
  box.setAttribute('aria-label', 'Play video');
  box.innerHTML =
    `<img class="tv-embed__poster" alt="" loading="lazy" src="https://img.youtube.com/vi/${id}/hqdefault.jpg">` +
    '<span class="tv-embed__play" aria-hidden="true"></span>';
  return box;
}

/**
 * Replaces YouTube iframes in [root] with previews, and makes other iframes load lazily inside a box that
 * keeps their aspect ratio. Returns the number of previews made.
 */
export function prepareEmbeds(root) {
  let previews = 0;
  for (const iframe of Array.from(root.querySelectorAll('iframe'))) {
    const id = youtubeId(iframe.getAttribute('src'));
    if (id) {
      iframe.replaceWith(preview(iframe, id));
      previews += 1;
      continue;
    }
    iframe.setAttribute('loading', 'lazy');
    const box = iframe.ownerDocument.createElement('div');
    box.className = 'tv-embed tv-embed--frame';
    box.style.aspectRatio = aspectRatio(iframe);
    iframe.replaceWith(box);
    box.appendChild(iframe);
  }
  return previews;
}

/** Turns a preview into a live player and the previously live one back into a preview. */
export function activateEmbed(box) {
  const root = box.ownerDocument;
  for (const live of Array.from(root.querySelectorAll('.tv-embed--live'))) {
    if (live === box) continue;
    const id = youtubeId(live.dataset.src);
    const iframe = root.createElement('iframe');
    iframe.setAttribute('src', live.dataset.src);
    live.replaceWith(preview(iframe, id));
  }

  const iframe = root.createElement('iframe');
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
