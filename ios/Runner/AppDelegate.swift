import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // 1. 先にプラグイン全体の基盤をレジスター
    GeneratedPluginRegistrant.register(with: self)

    // 🟢 解決の鍵：直接キャストせず、下部に新設したヘルパー関数で階層の奥底から100%確実に取得します
    if let controller = findFlutterViewController(from: window?.rootViewController) {
        let channel = FlutterMethodChannel(name: "app3.kportal/live_notification", binaryMessenger: controller.binaryMessenger)

        channel.setMethodCallHandler({
          (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in

          switch call.method {
          case "scheduleIOSLocalNotification":
              // 🟢 Hamanaが組んでくれたNSNumberによる型安全キャッチ（100点満点です）
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
    } else {
        // 万が一見つからなかった場合のデバッグログ
        print("🚨 ALERT: FlutterViewController could not be found in active hierarchy.")
    }

    // 3. 非同期で通知権限をリクエスト
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // 🟢 追記：カメラプラグイン等の階層いじりを完全に無力化する「再帰探索ヘルパー」
  private func findFlutterViewController(from rootVC: UIViewController?) -> FlutterViewController? {
      if let fvc = rootVC as? FlutterViewController { return fvc }
      if let nav = rootVC as? UINavigationController { return findFlutterViewController(from: nav.visibleViewController) }
      if let tab = rootVC as? UITabBarController { return findFlutterViewController(from: tab.selectedViewController) }
      if let children = rootVC?.children {
          for child in children {
              if let fvc = findFlutterViewController(from: child) { return fvc }
          }
      }
      return nil
  }
}