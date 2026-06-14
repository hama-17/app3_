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

    // 🟢 解決の鍵：大元の初期化（super.application）を先に走らせて、
    // iOS側の画面の土台（window と rootViewController）を100%確実にこの世に生成させます。
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // 2. 土台が完全に完成した「直後」だからこそ、安全に ViewController を取得して窓口をドッキングできる
    if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(name: "app3.kportal/live_notification", binaryMessenger: controller.binaryMessenger)

        channel.setMethodCallHandler({
          (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in

          switch call.method {
          case "scheduleIOSLocalNotification":
              guard let args = call.arguments as? [String: Any],
                    let id = args["id"] as? Int,
                    let triggerTimeMillis = args["triggerTimeMillis"] as? Int64,
                    let params = args["params"] as? [String: Any] else {
                  result(FlutterError(code: "INVALID_ARGS", message: "Arguments mapping failed", details: nil))
                  return
              }

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
    }

    // 3. 非同期で通知権限をリクエスト（メインスレッドのUI描画を絶対に邪魔しない安全な位置へ配置）
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

    return result
  }
}