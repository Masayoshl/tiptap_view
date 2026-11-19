import 'dart:async';

import 'package:flutter/foundation.dart';

/// Handles an event a bundle's extension sends with `runtime.emit(name, payload)`.
typedef TiptapEventHandler = void Function(Map<String, Object?> payload);

/// Answers a request a bundle's extension sends with `await runtime.request(name, payload)`. The result
/// goes back to the page as JSON; a thrown error rejects the page's promise with its message.
typedef TiptapRequestHandler = FutureOr<Object?> Function(Map<String, Object?> payload);

/// The Dart side of an extension in the bundle.
///
/// The extension itself, its schema and behavior, is JavaScript built into the bundle. This class names it,
/// so the view can tell when the bundle lacks an extension the app relies on, routes the events the
/// extension sends to Dart, and answers its requests. Later it is also where an extension's toolbar items and native widgets go.
@immutable
class TiptapExtension {
  const TiptapExtension(this.name, {this.events = const {}, this.requests = const {}});

  /// The name of the extension in the bundle, as in `Node.create({ name })`.
  final String name;

  /// Handlers for events by name. Built-in events (`ready`, `height`, `linkTap`…) are not routed here.
  final Map<String, TiptapEventHandler> events;

  /// Handlers for requests by name. The first extension with a handler for a name answers it; a request
  /// nobody handles is rejected in the page.
  final Map<String, TiptapRequestHandler> requests;

  @override
  String toString() => 'TiptapExtension($name)';
}
