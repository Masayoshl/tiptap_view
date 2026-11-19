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
