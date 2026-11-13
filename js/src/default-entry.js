import { createRuntime, defaultExtensions } from './index.js';

createRuntime({ name: 'default', extensions: defaultExtensions() });
