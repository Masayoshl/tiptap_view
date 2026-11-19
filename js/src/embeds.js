// Embedded frames in the view: each one loads lazily inside a box that keeps its aspect ratio. Players
// that deserve a still preview instead of a live frame are view hooks of their own (youtube-preview.js).

/** The CSS aspect ratio of a frame from its width and height attributes; 16 / 9 without them. */
export function aspectRatio(element) {
  const width = Number(element.getAttribute('width'));
  const height = Number(element.getAttribute('height'));
  return width > 0 && height > 0 ? `${width} / ${height}` : '16 / 9';
}

/** Puts every iframe in [root] that is not in an embed box yet into one, loading lazily. */
export function prepareFrames(root) {
  for (const iframe of Array.from(root.querySelectorAll('iframe'))) {
    if (iframe.parentElement && iframe.parentElement.classList.contains('tv-embed')) continue;
    iframe.setAttribute('loading', 'lazy');
    const box = iframe.ownerDocument.createElement('div');
    box.className = 'tv-embed tv-embed--frame';
    box.style.aspectRatio = aspectRatio(iframe);
    iframe.replaceWith(box);
    box.appendChild(iframe);
  }
}
