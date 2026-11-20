import Flutter
import ObjectiveC
import UIKit

/// The native things `tiptap_view` needs from WebKit's private `WKContentView`, which `webview_flutter` has no
/// API for:
///
/// - hiding the bar iOS puts above the keyboard of a WebView (the arrows and Done): the view's
///   `inputAccessoryView` getter answers `nil` while the app asks for the bar to be hidden;
/// - bringing the keyboard up when the editor is focused from code (`TiptapEditorController.focus`, a
///   toolbar button): WebKit shows it only for a focus the user started with a tap in the page, so the view's
///   `_elementDidFocus:userIsInteracting:…` is told the user is interacting while the app asks for it.
///
/// Nothing else of the view changes. When WebKit has no such class or method (a future iOS), the plugin
/// does nothing and says so to Dart.
public class TiptapViewPlugin: NSObject, FlutterPlugin {
  private static var hidden = false
  private static var installed = false
  private static var focusShowsKeyboard = false
  private static var focusInstalled = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tiptap_view/keyboard_accessory", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TiptapViewPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setAccessoryHidden":
      guard let hidden = call.arguments as? Bool else {
        result(FlutterError(code: "bad-arguments", message: "A bool is expected", details: nil))
        return
      }
      result(TiptapViewPlugin.setAccessoryHidden(hidden))
    case "setFocusShowsKeyboard":
      guard let value = call.arguments as? Bool else {
        result(FlutterError(code: "bad-arguments", message: "A bool is expected", details: nil))
        return
      }
      result(TiptapViewPlugin.setFocusShowsKeyboard(value))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Returns whether the bar can be controlled on this iOS.
  private static func setAccessoryHidden(_ value: Bool) -> Bool {
    guard installIfNeeded() else { return false }
    hidden = value
    // A keyboard that is already up keeps its bar until its input views are asked for again.
    firstResponder()?.reloadInputViews()
    return true
  }

  /// The view that has the keyboard, if any.
  private static func firstResponder() -> UIResponder? {
    func search(_ view: UIView) -> UIResponder? {
      if view.isFirstResponder { return view }
      for subview in view.subviews {
        if let found = search(subview) { return found }
      }
      return nil
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let found = search(window) { return found }
      }
    }
    return nil
  }

  private static func installIfNeeded() -> Bool {
    if installed { return true }
    let selector = #selector(getter: UIResponder.inputAccessoryView)
    guard let target = NSClassFromString("WKContentView"),
          let method = class_getInstanceMethod(target, selector),
          let types = method_getTypeEncoding(method) else { return false }
    typealias Getter = @convention(c) (AnyObject, Selector) -> UIView?
    let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
    let replacement: @convention(block) (AnyObject) -> UIView? = { view in
      hidden ? nil : original(view, selector)
    }
    // Set on the class itself: if the getter is inherited, only this class gets the new one.
    class_replaceMethod(target, selector, imp_implementationWithBlock(replacement), types)
    installed = true
    return true
  }

  /// Returns whether the keyboard can be brought up from code on this iOS.
  private static func setFocusShowsKeyboard(_ value: Bool) -> Bool {
    guard installFocusIfNeeded() else { return false }
    focusShowsKeyboard = value
    return true
  }

  private static func installFocusIfNeeded() -> Bool {
    if focusInstalled { return true }
    guard let target = NSClassFromString("WKContentView") else { return false }

    // iOS 13 and later.
    let current = NSSelectorFromString("_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:")
    if let method = class_getInstanceMethod(target, current), let types = method_getTypeEncoding(method) {
      typealias Focus = @convention(c) (AnyObject, Selector, UnsafeRawPointer?, Bool, Bool, UInt, AnyObject?) -> Void
      let original = unsafeBitCast(method_getImplementation(method), to: Focus.self)
      let replacement: @convention(block) (AnyObject, UnsafeRawPointer?, Bool, Bool, UInt, AnyObject?) -> Void = {
        view, element, interacting, blurPrevious, activityChanges, userObject in
        original(view, current, element, interacting || focusShowsKeyboard, blurPrevious, activityChanges, userObject)
      }
      class_replaceMethod(target, current, imp_implementationWithBlock(replacement), types)
      focusInstalled = true
      return true
    }

    // iOS 12.2.
    let older = NSSelectorFromString("_elementDidFocus:userIsInteracting:blurPreviousNode:changingActivityState:userObject:")
    if let method = class_getInstanceMethod(target, older), let types = method_getTypeEncoding(method) {
      typealias Focus = @convention(c) (AnyObject, Selector, UnsafeRawPointer?, Bool, Bool, Bool, AnyObject?) -> Void
      let original = unsafeBitCast(method_getImplementation(method), to: Focus.self)
      let replacement: @convention(block) (AnyObject, UnsafeRawPointer?, Bool, Bool, Bool, AnyObject?) -> Void = {
        view, element, interacting, blurPrevious, changingState, userObject in
        original(view, older, element, interacting || focusShowsKeyboard, blurPrevious, changingState, userObject)
      }
      class_replaceMethod(target, older, imp_implementationWithBlock(replacement), types)
      focusInstalled = true
      return true
    }
    return false
  }
}
