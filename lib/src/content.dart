import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A document to show: HTML, as published pages store it, or TipTap JSON.
@immutable
sealed class TiptapContent {
  const TiptapContent();

  /// HTML as it is, the way a web reader shows a published page. It is sanitized before it is shown
  /// unless [sanitize] is false; turn that off only for markup the app produced itself.
  const factory TiptapContent.html(String html, {bool sanitize}) = TiptapHtmlContent;

  /// TipTap JSON (`{"type": "doc", "content": [...]}`), rendered with the schema of the bundle.
  /// Node types the bundle does not know make the view report an error instead of dropping them silently.
  const factory TiptapContent.json(Map<String, Object?> json) = TiptapJsonContent;

  /// The message the runtime's `setContent` method takes.
  Map<String, Object?> toParams();
}

final class TiptapHtmlContent extends TiptapContent {
  const TiptapHtmlContent(this.html, {this.sanitize = true});

  final String html;
  final bool sanitize;

  @override
  Map<String, Object?> toParams() => {'format': 'html', 'content': html, 'sanitize': sanitize};

  @override
  bool operator ==(Object other) =>
      other is TiptapHtmlContent && other.html == html && other.sanitize == sanitize;

  @override
  int get hashCode => Object.hash(html, sanitize);
}

final class TiptapJsonContent extends TiptapContent {
  const TiptapJsonContent(this.json);

  final Map<String, Object?> json;

  @override
  Map<String, Object?> toParams() => {'format': 'json', 'content': json};

  // JSON documents are compared by value, so rebuilding a widget with an equal map does not re-render.
  @override
  bool operator ==(Object other) =>
      other is TiptapJsonContent && (identical(other.json, json) || jsonEncode(other.json) == jsonEncode(json));

  @override
  int get hashCode => jsonEncode(json).hashCode;
}
