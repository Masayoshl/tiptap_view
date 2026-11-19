// The example app's own bundle: the default extensions, the official Details node and a custom Callout
// node. It shows how an app adds extensions; build it with `npm run build:example` in ../../js.
import { Node, mergeAttributes } from '@tiptap/core';
import { Details, DetailsContent, DetailsSummary } from '@tiptap/extension-details';
import { createRuntime, defaultEmbeds, defaultExtensions, defaultViewHooks } from 'tiptap-view-runtime';
import './callout.css';

const Callout = Node.create({
  name: 'callout',
  group: 'block',
  content: 'block+',
  addAttributes() {
    return { tone: { default: 'info', parseHTML: element => element.getAttribute('data-tone') || 'info' } };
  },
  parseHTML: () => [{ tag: 'div[data-type="callout"]' }],
  renderHTML: ({ node, HTMLAttributes }) => [
    'div',
    mergeAttributes(HTMLAttributes, { 'data-type': 'callout', 'data-tone': node.attrs.tone }),
    0,
  ],
});

const runtime = createRuntime({
  name: 'example',
  schemaVersion: 1,
  extensions: [...defaultExtensions(), Details, DetailsSummary, DetailsContent, Callout],
  viewHooks: defaultViewHooks(),
  embeds: defaultEmbeds(),
});

// An extension event: Dart routes it to the handler of the `callout` TiptapExtension.
document.addEventListener('click', event => {
  const callout = event.target instanceof Element && event.target.closest('[data-type="callout"]');
  if (callout) runtime.emit('calloutTap', { tone: callout.getAttribute('data-tone'), text: callout.textContent.trim() });
});
