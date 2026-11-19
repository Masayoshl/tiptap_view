import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

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

  /// Runs TipTap's command [name] (`toggleBold`, `toggleHeading`, `setLink`, an app extension's own) with
  /// [argument], focusing the editor first. Returns whether it did something.
  ///
  ///     controller.command('toggleHeading', {'level': 2});
  ///     controller.command('setLink', {'href': url});
  Future<bool> command(String name, [Object? argument]) => commandWith(name, [?argument]);

  /// [command] with any number of arguments, and without focusing the editor when [focus] is false.
  Future<bool> commandWith(String name, List<Object?> arguments, {bool focus = true}) async =>
      await call('command', {'name': name, 'args': arguments, 'focus': focus}) == true;

  /// Whether [command] would do something now: for disabled toolbar buttons.
  Future<bool> canRun(String name, [Object? argument]) async =>
      await call('canRun', {'name': name, 'args': [?argument]}) == true;

  /// The commands the bundle's extensions have.
  Future<List<String>> commands() async => [for (final name in await call('commands') as List) '$name'];

  // Uploads -------------------------------------------------------------------------------------------

  int _uploadCount = 0;
  final Map<String, ({Future<TiptapUploadedImage> Function() upload, Completer<bool> done})> _uploads = {};

  /// Uploads an image the app picked and puts it at the selection.
  ///
  /// The editor shows a placeholder meanwhile, with [preview] (image bytes, of type [previewType]) when
  /// given; the placeholder is not part of the document, and `getContent` reports it in `errors`. [upload]
  /// is the app's own upload. When it throws, the placeholder shows the failure with Retry, which calls
  /// [upload] again, and Remove. Completes with true once the image is in the document, and false when the
  /// placeholder was removed or its document replaced.
  Future<bool> uploadImage(Future<TiptapUploadedImage> Function() upload, {Uint8List? preview, String previewType = 'image/jpeg'}) async {
    final id = 'upload-${++_uploadCount}';
    await call('beginUpload', {'id': id, 'preview': preview == null ? null : 'data:$previewType;base64,${base64Encode(preview)}'});
    final done = Completer<bool>();
    _uploads[id] = (upload: upload, done: done);
    unawaited(_runUpload(id));
    return done.future;
  }

  Future<void> _runUpload(String id) async {
    final entry = _uploads[id];
    if (entry == null) return;
    TiptapUploadedImage image;
    try {
      image = await entry.upload();
    } catch (error) {
      if (_uploads.containsKey(id)) unawaited(call('failUpload', {'id': id, 'message': '$error'}).catchError((_) => null));
      return;
    }
    if (_uploads.remove(id) == null) return;
    try {
      entry.done.complete(await call('finishUpload', {'id': id, ...image.toParams()}) == true);
    } catch (error, stack) {
      entry.done.completeError(error, stack);
    }
  }

  /// Used by the editor: the user tapped Retry or Remove on a failed placeholder.
  void handleUploadEvent(String name, Map<String, Object?> payload) {
    final id = '${payload['id']}';
    switch (name) {
      case 'uploadRetry':
        unawaited(_runUpload(id));
      case 'uploadCancel':
        _uploads.remove(id)?.done.complete(false);
    }
  }

  // Links and embeds ----------------------------------------------------------------------------------

  /// The link at the selection, or the selected text when there is none: what a link dialog starts from.
  Future<TiptapLink> getLink() async => TiptapLink.fromPayload(Map<String, Object?>.from(await call('getLink') as Map));

  /// Makes the selection, or the whole link the selection is in, a link to [href]. With [text], that text
  /// replaces it; with nothing selected outside a link, [text] (or [href]) is inserted as the link.
  /// [attributes] go on the link mark (`title`, an app's `data-*`); ones the mark does not declare are
  /// refused with a [TiptapCallException] rather than lost.
  Future<bool> setLink(String href, {Map<String, Object?> attributes = const {}, String? text}) async =>
      await call('setLink', {'href': href, 'attributes': attributes, 'text': ?text}) == true;

  /// Removes the link the selection is in.
  Future<bool> removeLink() async => await call('removeLink') == true;

  /// Puts an embed for [url] at the selection, as the bundle's embed resolvers turn it into a node.
  /// Returns the node type, or null when no resolver knows the URL.
  Future<String?> insertEmbed(String url) async {
    final result = Map<String, Object?>.from(await call('insertEmbed', {'url': url}) as Map);
    return result['inserted'] == true ? result['type'] as String? : null;
  }

  final ValueNotifier<TiptapEditorState?> _state = ValueNotifier(null);

  /// The editor's toolbar state, updated after every change; null while no document is open. Toolbars
  /// listen to it with a `ValueListenableBuilder`.
  ValueListenable<TiptapEditorState?> get state => _state;

  /// Used by the editor.
  void updateState(TiptapEditorState? state) => _state.value = state;

  @override
  void detach() {
    super.detach();
    _state.value = null;
    // The page went away, and the placeholders with it.
    for (final entry in _uploads.values) {
      entry.done.complete(false);
    }
    _uploads.clear();
  }

  void dispose() => _state.dispose();
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
