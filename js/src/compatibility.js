// Whether a TipTap JSON document fits a schema well enough to edit it without losing anything on save.
//
// TipTap itself is no help here: an unknown node or mark type makes the editor start with an empty
// document (only a console warning), and an attribute the schema does not declare is dropped without a
// word. Both would be saved. So the editor refuses such a document, and says why.

/**
 * Returns null when [json] fits [schema], or what does not fit:
 *
 *   { reason: 'newerSchema' | 'unknownTypes' | 'unknownAttributes', types, attributes,
 *     documentVersion, bundleVersion }
 *
 * `types` are node and mark type names the schema lacks; `attributes` are `type.attribute` keys it does
 * not declare. Versions are compared only when both are numbers: a document from a newer schema than the
 * bundle's is refused even when every name in it happens to be known.
 */
export function incompatibility(json, schema, { documentVersion = null, bundleVersion = null } = {}) {
  const types = new Set();
  const attributes = new Set();

  const visit = (item, kind) => {
    const type = kind === 'mark' ? schema.marks[item.type] : schema.nodes[item.type];
    if (!type) {
      types.add(String(item.type));
      return false;
    }
    for (const key of Object.keys(item.attrs || {})) {
      if (!(key in type.attrs)) attributes.add(`${item.type}.${key}`);
    }
    return true;
  };

  const stack = [json];
  while (stack.length) {
    const node = stack.pop();
    if (!node || typeof node !== 'object') continue;
    visit(node, 'node');
    for (const mark of node.marks || []) visit(mark, 'mark');
    for (const child of node.content || []) stack.push(child);
  }

  const newer = typeof documentVersion === 'number' && typeof bundleVersion === 'number' && documentVersion > bundleVersion;
  if (!newer && !types.size && !attributes.size) return null;
  return {
    reason: newer ? 'newerSchema' : types.size ? 'unknownTypes' : 'unknownAttributes',
    types: [...types].sort(),
    attributes: [...attributes].sort(),
    documentVersion,
    bundleVersion,
  };
}
