import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // 1. プラグイン全体の基盤をレジスター
    GeneratedPluginRegistrant.register(with: self)

    // 🟢【王道回帰】Flutter公式のデフォルトテンプレートと全く同じ「強制キャスト」に戻します。
    // plistの権限が揃った今、この王道スタイルが一番スレッドのデッドロック（窒息）を起こさず、
    // Dartの起動よりも確実に先回りでMethodChannelを100%開通させることができます。
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "app3.kportal/live_notification", binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler({
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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}