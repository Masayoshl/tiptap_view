import 'dart:async';

import 'events.dart';

/// What the controllers of `TiptapView` and `TiptapEditor` share: calls into the runtime, conversions with
/// the bundle's schema, and methods a bundle registered itself. Calls made before the widget's runtime is
/// ready wait for it.
abstract class TiptapRuntimeController {
  _Binding? _binding;
  Completer<void> _attached = Completer<void>();

  /// Whether a view is using this controller and its runtime is ready.
  bool get isReady => _binding != null;

  /// Calls [method] in the runtime and returns its result, decoded from JSON.
  /// Throws a [TiptapCallException] when the runtime reports an error.
  Future<Object?> call(String method, [Map<String, Object?> params = const {}]) async {
    while (_binding == null) {
      await _attached.future;
    }
    return _binding!(method, params);
  }

  /// Converts [html] to TipTap JSON with the bundle's schema. Markup the schema does not know is dropped,
  /// as the TipTap editor drops it.
  Future<Map<String, Object?>> htmlToJson(String html) async =>
      Map<String, Object?>.from(await call('htmlToJson', {'html': html}) as Map);

  /// Renders TipTap JSON to HTML with the bundle's schema.
  Future<String> jsonToHtml(Map<String, Object?> json) async => '${await call('jsonToHtml', {'json': json})}';

  /// Names of all node types in the bundle's schema.
  Future<List<String>> nodeTypes() async => [for (final name in await call('nodeTypes') as List) '$name'];

  // Used by the view.

  void attach(Future<Object?> Function(String method, Map<String, Object?> params) binding) {
    _binding = binding;
    if (!_attached.isCompleted) _attached.complete();
  }

  void detach() {
    _binding = null;
    if (_attached.isCompleted) _attached = Completer<void>();
  }
}

/// Calls into the runtime of a [TiptapView]: what every controller has, the shown HTML, and hiding images.
class TiptapViewController extends TiptapRuntimeController {
  /// The HTML the view shows now, after sanitizing and the view's own changes (embed previews and the like).
  Future<String> getHtml() async => '${await call('getHtml')}';

  /// Hides the image at [index] (see [TiptapImageTap.index]) in place, or shows it again. The space it takes
  /// stays, so nothing moves: meant for while a copy of the image is shown elsewhere, flying into a viewer.
  /// Returns false when there is no such image.
  Future<bool> setImageHidden(int index, {required bool hidden}) async =>
      await call('setImageHidden', {'index': index, 'hidden': hidden}) == true;
}

/// Calls into the runtime of a `TiptapEditor`: what every controller has, and the document being edited.
class TiptapEditorController extends TiptapRuntimeController {
  /// The document as it is now, as JSON and as the schema's HTML, with what keeps it from being saved
  /// (the bundle's `validateForSave`). Throws a [TiptapCallException] when no document is open.
  Future<TiptapEditorContent> getContent() async =>
      TiptapEditorContent.fromPayload(Map<String, Object?>.from(await call('getContent') as Map));

  /// Turns editing off (the document stays, read-only) or back on.
  Future<void> setEditable(bool editable) => call('setEditable', {'editable': editable});

  /// Puts the caret into the document: at `start`, `end` (the default) or `all` of it selected.
  Future<void> focus({String position = 'end'}) => call('focus', {'position': position});

  Future<void> blur() => call('blur');
}

typedef _Binding = Future<Object?> Function(String method, Map<String, Object?> params);

/// The runtime answered a call with an error.
class TiptapCallException implements Exception {
  const TiptapCallException(this.method, this.message);

  final String method;
  final String message;

  @override
  String toString() => 'TiptapCallException($method): $message';
}
