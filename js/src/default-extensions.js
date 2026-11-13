import StarterKit from '@tiptap/starter-kit';
import Image from '@tiptap/extension-image';
import { TableKit } from '@tiptap/extension-table';
import Youtube from '@tiptap/extension-youtube';
import { TextStyleKit } from '@tiptap/extension-text-style';
import TextAlign from '@tiptap/extension-text-align';
import { TaskList, TaskItem } from '@tiptap/extension-list';

/**
 * The extensions the default bundle knows. An app bundle usually starts from these and adds its own,
 * so that standard content keeps working: `[...defaultExtensions(), MyNode]`.
 * It returns fresh instances each call, because a configured extension must not be shared between schemas.
 */
export function defaultExtensions() {
  return [
    StarterKit,
    Image,
    TableKit,
    Youtube,
    TextStyleKit,
    TextAlign.configure({ types: ['heading', 'paragraph'] }),
    TaskList,
    TaskItem.configure({ nested: true }),
  ];
}
