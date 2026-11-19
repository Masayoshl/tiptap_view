// Builds a runtime bundle for the tiptap_view Flutter package.
//
//   node build.mjs                                   → the package's default bundle in ../assets/default/
//   node build.mjs --entry <file> --out <dir>        → an app bundle: its entry calls createRuntime itself
//
// A bundle is one runtime.js (runtime, TipTap and the extensions together, so there is one copy of
// @tiptap/core) and one runtime.css (the base styles, then any CSS the entry imports).
//
// An app's extensions often live in its own repository, next to its web editor, with a node_modules of
// their own. Resolved from there, `@tiptap/core` would be a second copy, with a schema the runtime's
// copy does not recognize. So every TipTap and ProseMirror import goes to the runtime's copy when it has
// the package; packages only the app has (an extension the runtime does not ship) come from the app.
import { build } from 'esbuild';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

const oneTiptap = {
  name: 'one-tiptap',
  setup(build) {
    build.onResolve({ filter: /^(@tiptap\/|prosemirror-)/ }, async args => {
      if (args.pluginData === 'one-tiptap') return undefined;
      const result = await build.resolve(args.path, { kind: args.kind, resolveDir: here, pluginData: 'one-tiptap' });
      return result.errors.length ? undefined : { path: result.path, sideEffects: result.sideEffects };
    });
  },
};
const args = process.argv.slice(2);
const option = name => {
  const index = args.indexOf(`--${name}`);
  return index >= 0 ? args[index + 1] : undefined;
};

const entry = resolve(option('entry') ?? resolve(here, 'src/default-entry.js'));
const outdir = resolve(option('out') ?? resolve(here, '../assets/default'));
const version = JSON.parse(readFileSync(resolve(here, 'package.json'), 'utf8')).version;
const tiptapVersion = JSON.parse(readFileSync(resolve(here, 'node_modules/@tiptap/core/package.json'), 'utf8')).version;

await build({
  entryPoints: { runtime: entry },
  bundle: true,
  minify: true,
  format: 'iife',
  target: ['safari15', 'chrome100'],
  outdir,
  // Apps import the runtime by name and resolve TipTap from here, so their bundle has the same copy.
  alias: { 'tiptap-view-runtime': resolve(here, 'src/index.js') },
  nodePaths: [resolve(here, 'node_modules')],
  inject: [resolve(here, 'src/base-styles.js')],
  plugins: [oneTiptap],
  define: {
    __RUNTIME_VERSION__: JSON.stringify(version),
    __TIPTAP_VERSION__: JSON.stringify(tiptapVersion),
  },
  // The bundle is inlined into the host page, inside a <script> element.
  supported: { 'inline-script': false },
  legalComments: 'none',
  logLevel: 'info',
});
