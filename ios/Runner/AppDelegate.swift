import Flutter
import UIKit
import UserNotifications
import workmanager
//ios/runner/appdelegate.swift
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // プラグイン全体の基盤をレジスター
    GeneratedPluginRegistrant.register(with: self)

    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
    }

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController

    // ─── 1. 既存：ローカル通知用 MethodChannel ───
    let notificationChannel = FlutterMethodChannel(name: "app3.kportal/live_notification", binaryMessenger: controller.binaryMessenger)

    notificationChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in

      switch call.method {
      case "scheduleIOSLocalNotification":
          guard let args = call.arguments as? [String: Any],
                let idNum = args["id"] as? NSNumber,
                let timeNum = args["triggerTimeMillis"] as? NSNumber,
                let params = args["params"] as? [String: Any] else {
              result(FlutterError(code: "INVALID_ARGS", message: "Arguments mapping failed", details: nil))
              return
          }

          let id = idNum.intValue
          let triggerTimeMillis = timeNum.int64Value

          let title = params["title"] as? String ?? "予定"
          let subtitle = params["subtitle"] as? String ?? ""

          let content = UNMutableNotificationContent()
          content.title = title
          content.body = subtitle
          content.sound = UNNotificationSound.default

          let triggerDate = Date(timeIntervalSince1970: TimeInterval(triggerTimeMillis / 1000))
          let timeInterval = triggerDate.timeIntervalSinceNow

          if timeInterval > 0 {
              let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
              let request = UNNotificationRequest(identifier: String(id), content: content, trigger: trigger)

              UNUserNotificationCenter.current().add(request) { error in
                  if let error = error {
                      print("iOS Notification Schedule Error: \(error)")
                  }
              }
          }
          result(nil)

      case "cancelAllIOSLocalNotifications":
          UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
          result(nil)

      case "startLiveNotification":
          result(nil)

      default:
          result(FlutterMethodNotImplemented)
      }
    })

    // ─── 2. 🟢 追記：App Group クッキー同期用 MethodChannel ───
    let appGroupChannel = FlutterMethodChannel(name: "com.h.k.portal/app_group", binaryMessenger: controller.binaryMessenger)

    appGroupChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in

      // 🟢 お使いの App Group ID に合わせて変更（例: group.com.example.app3kportal など）
      let suiteName = "group.com.h.k.portal"
      let defaults = UserDefaults(suiteName: suiteName)

      switch call.method {
      case "getAppGroupCookie":
          let cookie = defaults?.string(forKey: "session_cookie")
          result(cookie)

      case "clearAppGroupCookie":
          defaults?.removeObject(forKey: "session_cookie")
          defaults?.synchronize()
          result(true)

      default:
          result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}