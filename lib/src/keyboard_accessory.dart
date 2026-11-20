import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The bar iOS shows above the keyboard of a WebView (the arrows and Done). An app with its own toolbar
/// hides it through `TiptapEditor.showKeyboardAccessory`; this is what that asks of the platform.
///
/// Editors count: the bar is hidden while any editor wants it hidden, and comes back with the last of them.
/// On platforms without the bar, or when the native side is missing, asking does nothing.
class TiptapKeyboardAccessory {
  const TiptapKeyboardAccessory._();

  static const channel = MethodChannel('tiptap_view/keyboard_accessory');

  static int _hiders = 0;

  /// An editor wants the bar hidden. Returns whether the platform could do it.
  static Future<bool> hide() async => ++_hiders > 1 || await _set(hidden: true);

  /// An editor no longer wants it hidden.
  static Future<void> release() async {
    if (_hiders == 0) return;
    if (--_hiders == 0) await _set(hidden: false);
  }

  static Future<bool> _set({required bool hidden}) async {
    try {
      return await channel.invokeMethod<bool>('setAccessoryHidden', hidden) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @visibleForTesting
  static void reset() => _hiders = 0;
}
