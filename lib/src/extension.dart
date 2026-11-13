import 'package:flutter/foundation.dart';

/// Handles an event a bundle's extension sends with `runtime.emit(name, payload)`.
typedef TiptapEventHandler = void Function(Map<String, Object?> payload);

/// The Dart side of an extension in the bundle.
///
/// The extension itself, its schema and behavior, is JavaScript built into the bundle. This class names it,
/// so the view can tell when the bundle lacks an extension the app relies on, and routes the events the
/// extension sends to Dart. Later it is also where an extension's toolbar items and native widgets go.
@immutable
class TiptapExtension {
  const TiptapExtension(this.name, {this.events = const {}});

  /// The name of the extension in the bundle, as in `Node.create({ name })`.
  final String name;

  /// Handlers for events by name. Built-in events (`ready`, `height`, `linkTap`…) are not routed here.
  final Map<String, TiptapEventHandler> events;

  @override
  String toString() => 'TiptapExtension($name)';
}
