import { createRuntime, defaultEmbeds, defaultExtensions, defaultViewHooks } from './index.js';

createRuntime({ name: 'default', extensions: defaultExtensions(), viewHooks: defaultViewHooks(), embeds: defaultEmbeds() });
