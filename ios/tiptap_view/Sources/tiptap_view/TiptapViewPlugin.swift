import Flutter
import ObjectiveC
import UIKit

/// The one native thing `tiptap_view` needs: letting the app hide the bar iOS puts above the keyboard of a
/// WebView (the arrows and Done). `webview_flutter` has no API for it, and the bar belongs to WebKit's
/// private `WKContentView`, so the plugin replaces that view's `inputAccessoryView` getter with one that
/// answers `nil` while the app asks for the bar to be hidden. Nothing else of the view changes. When WebKit
/// has no such class or method (a future iOS), the plugin does nothing and says so to Dart.
public class TiptapViewPlugin: NSObject, FlutterPlugin {
  private static var hidden = false
  private static var installed = false

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
}
