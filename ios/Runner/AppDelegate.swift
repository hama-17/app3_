import Flutter
import UIKit
import UserNotifications // 🟢 追記：通知センターを動かすために必要

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // 🟢 追記：アプリ起動時にiOSの通知権限ポップアップを自動で出す
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        if let error = error {
            print("Notification Authorization Error: \(error)")
        }
    }

    // 🟢 追記：Dart側の「LiveNotificationService」と通信する窓口（MethodChannel）を開設
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "app3.kportal/live_notification", binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in

      switch call.method {
      case "scheduleIOSLocalNotification":
          // Dartから送られてきた通知チケットをパース
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int,
                let triggerTimeMillis = args["triggerTimeMillis"] as? Int64,
                let params = args["params"] as? [String: Any] else {
              result(FlutterError(code: "INVALID_ARGS", message: "Arguments mapping failed", details: nil))
              return
          }

          let title = params["title"] as? String ?? "予定"
          let subtitle = params["subtitle"] as? String ?? ""

          // iOS用の通知コンテンツを作成
          let content = UNMutableNotificationContent()
          content.title = title
          content.body = subtitle
          content.sound = UNNotificationSound.default

          // 発火時刻（ミリ秒）から時間差（秒数）を逆算してタイマーをセット
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
          // 過去の予約を全消去して二重発火を防止
          UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
          result(nil)

      case "startLiveNotification":
          // Android特有のライブ常駐エフェクト命令なので、iOS側は無言で正常終了（スルー）させてエラーを防ぐ
          result(nil)

      default:
          result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}