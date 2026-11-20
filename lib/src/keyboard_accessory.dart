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

/// Whether focusing the editor from code brings the keyboard up on iOS. WebKit shows the keyboard only for a
/// focus the user started with a tap in the page, so `TiptapEditorController.focus` (from a toolbar button,
/// say) moved the caret but left the keyboard down. Editors that want it set
/// `TiptapEditor.focusShowsKeyboard`; it is on while any of them is shown.
///
/// On platforms without the restriction, or when the native side is missing, asking does nothing.
class TiptapKeyboardFocus {
  const TiptapKeyboardFocus._();

  static int _holders = 0;

  /// An editor wants focus from code to bring the keyboard up. Returns whether the platform could do it.
  static Future<bool> hold() async => ++_holders > 1 || await _set(true);

  /// An editor no longer wants it.
  static Future<void> release() async {
    if (_holders == 0) return;
    if (--_holders == 0) await _set(false);
  }

  static Future<bool> _set(bool value) async {
    try {
      return await TiptapKeyboardAccessory.channel.invokeMethod<bool>('setFocusShowsKeyboard', value) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @visibleForTesting
  static void reset() => _holders = 0;
}
