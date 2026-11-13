// What an app bundle imports to build its own runtime:
//
//   import { createRuntime, defaultExtensions } from 'tiptap-view-runtime';
//   createRuntime({ name: 'my-app', extensions: [...defaultExtensions(), MyNode], schemaVersion: 1 });
export { createRuntime, PROTOCOL_VERSION } from './runtime.js';
export { defaultExtensions } from './default-extensions.js';
