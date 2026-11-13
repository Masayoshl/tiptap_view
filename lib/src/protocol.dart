import 'dart:convert';

/// Messages between Dart and the JS runtime.
///
/// Dart calls the runtime with `window.tiptapView.receive({id, method, params})`; the runtime answers with
/// `{type: "response", id, result | error}` and sends `{type: "event", event, payload}` on its own. Every
/// message from the runtime carries the session token Dart put into the host page, so messages from
/// anything else in the page, an embedded frame for one, are dropped.
abstract final class TiptapProtocol {
  /// The protocol this package speaks; the runtime announces its own in the `ready` event.
  static const int version = 1;

  /// The JavaScript channel the runtime posts to.
  static const String channel = 'TiptapViewBridge';

  /// The script that delivers [method] to the runtime.
  static String call(String id, String method, Map<String, Object?> params) {
    // jsonEncode output is a valid JavaScript literal.
    return 'window.tiptapView && window.tiptapView.receive(${jsonEncode({'id': id, 'method': method, 'params': params})});';
  }

  /// Parses a message posted by the runtime. Returns null for anything malformed or without [token].
  static TiptapMessage? parse(String text, {required String token}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?> || decoded['token'] != token) return null;
    switch (decoded['type']) {
      case 'event':
        final event = decoded['event'];
        if (event is! String) return null;
        final payload = decoded['payload'];
        return TiptapEventMessage(event, payload is Map<String, Object?> ? payload : const {});
      case 'response':
        final id = decoded['id'];
        if (id is! String) return null;
        final error = decoded['error'];
        return TiptapResponseMessage(id, result: decoded['result'], error: error is String ? error : null);
    }
    return null;
  }
}

sealed class TiptapMessage {
  const TiptapMessage();
}

final class TiptapEventMessage extends TiptapMessage {
  const TiptapEventMessage(this.event, this.payload);

  final String event;
  final Map<String, Object?> payload;
}

final class TiptapResponseMessage extends TiptapMessage {
  const TiptapResponseMessage(this.id, {this.result, this.error});

  final String id;
  final Object? result;
  final String? error;
}
