import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// What the runtime says about itself once the page has loaded.
@immutable
class TiptapReadyInfo {
  const TiptapReadyInfo({
    required this.protocol,
    required this.runtimeVersion,
    required this.tiptapVersion,
    required this.bundle,
    required this.schemaVersion,
    required this.extensions,
    this.mode,
    this.modes = const [],
  });

  factory TiptapReadyInfo.fromPayload(Map<String, Object?> payload) => TiptapReadyInfo(
        protocol: (payload['protocol'] as num?)?.toInt() ?? 0,
        runtimeVersion: '${payload['runtimeVersion'] ?? ''}',
        tiptapVersion: '${payload['tiptapVersion'] ?? ''}',
        bundle: '${payload['bundle'] ?? ''}',
        schemaVersion: (payload['schemaVersion'] as num?)?.toInt(),
        extensions: [for (final name in (payload['extensions'] as List?) ?? const []) '$name'],
        mode: payload['mode'] as String?,
        modes: [for (final name in (payload['modes'] as List?) ?? const []) '$name'],
      );

  final int protocol;
  final String runtimeVersion;
  final String tiptapVersion;

  /// The name the bundle gave itself in `createRuntime`.
  final String bundle;

  /// The schema version the bundle declared, if any.
  final int? schemaVersion;

  /// Names of the top-level extensions in the bundle.
  final List<String> extensions;

  /// The mode the runtime started in (`view`), or null when the page asked for one the runtime lacks.
  final String? mode;

  /// The modes the runtime can start in.
  final List<String> modes;

  @override
  String toString() =>
      'TiptapReadyInfo(bundle: $bundle, runtime: $runtimeVersion, tiptap: $tiptapVersion, protocol: $protocol, '
      'schema: $schemaVersion, mode: $mode, extensions: $extensions)';
}

/// A tap on a link. The view never navigates by itself; the app decides what a link does.
@immutable
class TiptapLinkTap {
  const TiptapLinkTap({required this.href, required this.text, required this.attributes, required this.uri});

  factory TiptapLinkTap.fromPayload(Map<String, Object?> payload, {required Uri baseUri}) {
    final href = '${payload['href'] ?? ''}';
    return TiptapLinkTap(
      href: href,
      text: '${payload['text'] ?? ''}',
      attributes: _attributes(payload['attributes']),
      uri: Uri.tryParse(href) == null ? null : baseUri.resolve(href),
    );
  }

  /// The `href` exactly as written in the document, for instance `/space/page` or `#section`.
  final String href;
  final String text;

  /// All attributes of the link, such as `data-page-id`.
  final Map<String, String> attributes;

  /// [href] resolved against the view's base URL; null when it is not a valid URI.
  final Uri? uri;

  /// True when [href] points into the app's own content rather than another site: it is relative, or it
  /// has the base URL's origin.
  bool isInternal(Uri baseUri) {
    final resolved = uri;
    if (resolved == null) return false;
    return resolved.scheme == baseUri.scheme && resolved.host == baseUri.host && resolved.port == baseUri.port;
  }

  @override
  String toString() => 'TiptapLinkTap($href, $attributes)';
}

/// A tap on an image that is not inside a link.
@immutable
class TiptapImageTap {
  const TiptapImageTap({
    required this.src,
    required this.alt,
    required this.attributes,
    this.index,
    this.rect,
    this.globalRect,
  });

  /// [viewOrigin] is the view's top left on screen; it places [rect] on screen as [globalRect].
  factory TiptapImageTap.fromPayload(Map<String, Object?> payload, {Offset? viewOrigin}) {
    final box = payload['rect'];
    Rect? rect;
    if (box is Map) {
      double value(String key) => (box[key] as num?)?.toDouble() ?? 0;
      rect = Rect.fromLTWH(value('left'), value('top'), value('width'), value('height'));
      if (rect.isEmpty) rect = null;
    }
    return TiptapImageTap(
      src: '${payload['src'] ?? ''}',
      alt: '${payload['alt'] ?? ''}',
      attributes: _attributes(payload['attributes']),
      index: (payload['index'] as num?)?.toInt(),
      rect: rect,
      globalRect: rect == null || viewOrigin == null ? null : rect.shift(viewOrigin),
    );
  }

  final String src;
  final String alt;
  final Map<String, String> attributes;

  /// The image's position among the document's images; [TiptapViewController.setImageHidden] takes it.
  final int? index;

  /// Where the image is in the view, in logical pixels.
  final Rect? rect;

  /// Where the image is on screen at the moment of the tap: where a full-screen viewer can fly it from.
  final Rect? globalRect;

  @override
  String toString() => 'TiptapImageTap($src, index: $index, rect: $rect)';
}

/// Something went wrong: in the runtime (a script error, content it could not render) or in the view
/// (a bundle that speaks another protocol, an extension the app expects but the bundle lacks).
@immutable
class TiptapError {
  const TiptapError(this.message, {this.context, this.stack});

  factory TiptapError.fromPayload(Map<String, Object?> payload) => TiptapError(
        '${payload['message'] ?? 'Unknown error'}',
        context: payload['context'] as String?,
        stack: payload['stack'] as String?,
      );

  final String message;

  /// Where it happened: `setContent`, `window`, `protocol`, `extensions`…
  final String? context;
  final String? stack;

  @override
  String toString() => context == null ? 'TiptapError: $message' : 'TiptapError ($context): $message';
}

/// Any event from the runtime, including the ones the view also turns into typed callbacks.
@immutable
class TiptapEvent {
  const TiptapEvent(this.name, this.payload);

  final String name;
  final Map<String, Object?> payload;

  @override
  String toString() => 'TiptapEvent($name, $payload)';
}

Map<String, String> _attributes(Object? value) => {
      if (value is Map) for (final entry in value.entries) '${entry.key}': '${entry.value}',
    };

/// The document in a `TiptapEditor` changed. Edits are counted, not shipped: read the document with
/// `TiptapEditorController.getContent` when it is needed.
@immutable
class TiptapEditorChange {
  const TiptapEditorChange(this.version);

  /// How many edits the document has had since it was opened.
  final int version;

  @override
  String toString() => 'TiptapEditorChange($version)';
}

/// The document in a `TiptapEditor`, as `TiptapEditorController.getContent` reads it.
@immutable
class TiptapEditorContent {
  const TiptapEditorContent({required this.json, required this.html, required this.version, this.errors = const []});

  factory TiptapEditorContent.fromPayload(Map<String, Object?> payload) => TiptapEditorContent(
        json: Map<String, Object?>.from(payload['json'] as Map? ?? const {}),
        html: '${payload['html'] ?? ''}',
        version: (payload['version'] as num?)?.toInt() ?? 0,
        errors: List<Object?>.unmodifiable(payload['errors'] as List? ?? const []),
      );

  /// TipTap JSON: what to store, next to [html] and the bundle's schema version.
  final Map<String, Object?> json;

  /// The schema's HTML for the document.
  final String html;

  /// The edit count when it was read (see [TiptapEditorChange.version]).
  final int version;

  /// What keeps the document from being saved now, as the bundle's `validateForSave` reports it. Empty
  /// when it can be saved.
  final List<Object?> errors;

  bool get canSave => errors.isEmpty;

  @override
  String toString() => 'TiptapEditorContent(version: $version, errors: $errors)';
}

/// Why a document cannot be edited with the bundle's schema.
enum TiptapIncompatibility {
  /// The document was saved with a newer schema version than the bundle's.
  newerSchema,

  /// It has node or mark types the schema lacks.
  unknownTypes,

  /// Its nodes or marks have attributes the schema does not declare.
  unknownAttributes,
}

/// A document `TiptapEditor` refused to edit: saving it would lose what the schema cannot hold (TipTap
/// would drop it without a word). The editor stays empty and read-only; the app shows the document another
/// way, `TiptapView` with its saved HTML for one, and decides what to tell the user.
@immutable
class TiptapIncompatibleContent {
  const TiptapIncompatibleContent({
    required this.reason,
    this.types = const [],
    this.attributes = const [],
    this.documentVersion,
    this.bundleVersion,
  });

  factory TiptapIncompatibleContent.fromPayload(Map<String, Object?> payload) => TiptapIncompatibleContent(
        reason: TiptapIncompatibility.values.firstWhere(
          (value) => value.name == payload['reason'],
          orElse: () => TiptapIncompatibility.unknownTypes,
        ),
        types: [for (final type in (payload['types'] as List?) ?? const []) '$type'],
        attributes: [for (final key in (payload['attributes'] as List?) ?? const []) '$key'],
        documentVersion: (payload['documentVersion'] as num?)?.toInt(),
        bundleVersion: (payload['bundleVersion'] as num?)?.toInt(),
      );

  final TiptapIncompatibility reason;

  /// Node and mark types the schema lacks.
  final List<String> types;

  /// Attributes the schema does not declare, as `type.attribute`.
  final List<String> attributes;

  final int? documentVersion;
  final int? bundleVersion;

  @override
  String toString() =>
      'TiptapIncompatibleContent(${reason.name}, types: $types, attributes: $attributes, '
      'document: $documentVersion, bundle: $bundleVersion)';
}

/// A node around the selection in a `TiptapEditor`: its type and attributes.
@immutable
class TiptapNodeState {
  const TiptapNodeState(this.type, this.attrs);

  final String type;
  final Map<String, Object?> attrs;

  @override
  bool operator ==(Object other) =>
      other is TiptapNodeState && other.type == type && mapEquals(other.attrs, attrs);

  @override
  int get hashCode => Object.hash(type, Object.hashAllUnordered(attrs.entries.map((e) => Object.hash(e.key, e.value))));

  @override
  String toString() => 'TiptapNodeState($type, $attrs)';
}

/// What a toolbar needs from a `TiptapEditor`, sent after every change of the document, the selection or
/// the focus. Built from the schema's names, so an app's own nodes and marks are in it like TipTap's.
@immutable
class TiptapEditorState {
  const TiptapEditorState({
    this.version = 0,
    this.editable = false,
    this.focused = false,
    this.marks = const {},
    this.nodes = const [],
    this.canUndo = false,
    this.canRedo = false,
    this.selectionEmpty = true,
    this.selectionFrom = 0,
    this.selectionTo = 0,
    this.selectedNode,
  });

  factory TiptapEditorState.fromPayload(Map<String, Object?> payload) {
    final selection = payload['selection'] is Map ? Map<String, Object?>.from(payload['selection'] as Map) : const {};
    final marks = payload['marks'] is Map ? payload['marks'] as Map : const {};
    return TiptapEditorState(
      version: (payload['version'] as num?)?.toInt() ?? 0,
      editable: payload['editable'] == true,
      focused: payload['focused'] == true,
      marks: {
        for (final entry in marks.entries)
          '${entry.key}': Map<String, Object?>.unmodifiable(entry.value is Map ? entry.value as Map : const {}),
      },
      nodes: [
        for (final node in (payload['nodes'] as List?) ?? const [])
          if (node is Map)
            TiptapNodeState('${node['type']}', Map<String, Object?>.unmodifiable(node['attrs'] is Map ? node['attrs'] as Map : const {})),
      ],
      canUndo: payload['canUndo'] == true,
      canRedo: payload['canRedo'] == true,
      selectionEmpty: selection['empty'] != false,
      selectionFrom: (selection['from'] as num?)?.toInt() ?? 0,
      selectionTo: (selection['to'] as num?)?.toInt() ?? 0,
      selectedNode: selection['node'] as String?,
    );
  }

  /// The edit count (see [TiptapEditorChange.version]).
  final int version;
  final bool editable;
  final bool focused;

  /// Active marks at the selection, with their attributes: `{'bold': {}, 'link': {'href': …}}`.
  final Map<String, Map<String, Object?>> marks;

  /// The nodes around the selection, outermost first: `bulletList`, `listItem`, `paragraph`.
  final List<TiptapNodeState> nodes;

  final bool canUndo;
  final bool canRedo;
  final bool selectionEmpty;
  final int selectionFrom;
  final int selectionTo;

  /// The type of a selected node (an image, a video) rather than text; null for a text selection.
  final String? selectedNode;

  /// The innermost node around the selection: the block type (`paragraph`, `heading`…).
  TiptapNodeState? get block => nodes.isEmpty ? null : nodes.last;

  /// Whether a mark or a node around the selection is [name], with at least [attrs]:
  /// `isActive('bold')`, `isActive('heading', {'level': 2})`, `isActive('paragraph', {'textAlign': 'center'})`.
  bool isActive(String name, [Map<String, Object?> attrs = const {}]) {
    bool matches(Map<String, Object?> actual) => attrs.entries.every((entry) => actual[entry.key] == entry.value);
    final mark = marks[name];
    if (mark != null) return matches(mark);
    return nodes.any((node) => node.type == name && matches(node.attrs)) || (selectedNode == name && attrs.isEmpty);
  }

  @override
  bool operator ==(Object other) =>
      other is TiptapEditorState &&
      other.version == version &&
      other.editable == editable &&
      other.focused == focused &&
      mapEquals(other.marks.map((k, v) => MapEntry(k, v.toString())), marks.map((k, v) => MapEntry(k, v.toString()))) &&
      listEquals(other.nodes, nodes) &&
      other.canUndo == canUndo &&
      other.canRedo == canRedo &&
      other.selectionEmpty == selectionEmpty &&
      other.selectionFrom == selectionFrom &&
      other.selectionTo == selectionTo &&
      other.selectedNode == selectedNode;

  @override
  int get hashCode => Object.hash(version, editable, focused, marks.length, nodes.length, canUndo, canRedo, selectionFrom, selectionTo, selectedNode);

  @override
  String toString() => 'TiptapEditorState(marks: ${marks.keys.toList()}, block: ${block?.type}, undo: $canUndo, redo: $canRedo)';
}

/// An image the app has uploaded, for a `TiptapEditor` to put in the document.
@immutable
class TiptapUploadedImage {
  const TiptapUploadedImage(this.src, {this.attributes = const {}, this.node = 'image'});

  /// The image's URL, where it will be loaded from.
  final String src;

  /// More attributes of the image node, such as a media id. Ones the node does not declare are left out
  /// and reported, since TipTap would drop them silently.
  final Map<String, Object?> attributes;

  /// The image node type of the bundle's schema: `image`, or an app's own (`blockImage`).
  final String node;

  Map<String, Object?> toParams() => {'src': src, 'attributes': attributes, 'node': node};
}

/// An image file pasted into a `TiptapEditor`, for the app to upload.
@immutable
class TiptapImageFile {
  const TiptapImageFile({required this.bytes, required this.mimeType, this.name = ''});

  final Uint8List bytes;
  final String mimeType;

  /// The file name the clipboard gave, often empty.
  final String name;

  @override
  String toString() => 'TiptapImageFile($mimeType, ${bytes.length} bytes, $name)';
}

/// The link at the selection of a `TiptapEditor`, as `TiptapEditorController.getLink` reads it.
@immutable
class TiptapLink {
  const TiptapLink({required this.active, this.href, this.attributes = const {}, this.text = '', this.selectionEmpty = true});

  factory TiptapLink.fromPayload(Map<String, Object?> payload) => TiptapLink(
        active: payload['active'] == true,
        href: payload['href'] as String?,
        attributes: Map<String, Object?>.unmodifiable(payload['attributes'] is Map ? payload['attributes'] as Map : const {}),
        text: '${payload['text'] ?? ''}',
        selectionEmpty: payload['empty'] != false,
      );

  /// Whether the selection is inside a link; when it is not, [text] is the selected text.
  final bool active;
  final String? href;

  /// The link's other attributes (`target`, `rel`, `title`, an app's own).
  final Map<String, Object?> attributes;

  /// The link's text, or the selected text when there is no link.
  final String text;
  final bool selectionEmpty;

  @override
  String toString() => 'TiptapLink(active: $active, $href, "$text")';
}
