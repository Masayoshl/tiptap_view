// What an app bundle imports to build its own runtime:
//
//   import { createRuntime, defaultEmbeds, defaultExtensions, defaultViewHooks } from 'tiptap-view-runtime';
//   createRuntime({
//     name: 'my-app',
//     extensions: [...defaultExtensions(), MyNode],
//     viewHooks: defaultViewHooks(),
//     embeds: defaultEmbeds(),
//     schemaVersion: 1,
//   });
export { createRuntime, PROTOCOL_VERSION } from './runtime.js';
export { defaultEmbeds, defaultExtensions, defaultViewHooks } from './default-extensions.js';
export { youtubeEmbed, youtubePreview } from './youtube-preview.js';
