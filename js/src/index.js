// What an app bundle imports to build its own runtime:
//
//   import { createRuntime, defaultExtensions, defaultViewHooks } from 'tiptap-view-runtime';
//   createRuntime({
//     name: 'my-app',
//     extensions: [...defaultExtensions(), MyNode],
//     viewHooks: defaultViewHooks(),
//     schemaVersion: 1,
//   });
export { createRuntime, PROTOCOL_VERSION } from './runtime.js';
export { defaultExtensions, defaultViewHooks } from './default-extensions.js';
export { youtubePreview } from './youtube-preview.js';
