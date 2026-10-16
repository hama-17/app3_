import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let appGroupChannel = FlutterMethodChannel(name: "com.h.k.portal/app_group",
                                               binaryMessenger: controller.binaryMessenger)

    appGroupChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "getAppGroupCookie" {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.h.k.portal") {
          sharedDefaults.synchronize()
          let cookie = sharedDefaults.string(forKey: "session_cookie")
          result(cookie)
        } else {
          result(nil)
        }
      } else if call.method == "clearAppGroupCookie" {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.h.k.portal") {
          sharedDefaults.removeObject(forKey: "session_cookie")
          sharedDefaults.synchronize()
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}