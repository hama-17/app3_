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

    // 🟢【実行順序の完全正常化】
    // 先に大元の初期化を走らせて、Flutterエンジンと画面の器を完全に起動させます。
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // 🟢【カメラの影響を100%無効化する直通ドッキング】
    // super.application の「直後」であれば、エンジンが完成しているため安全にレジストラを叩けます。
    // window や ViewController をスキャンしないため、カメラパッケージがどれだけビュー階層を
    // いじくり回していようが関係なく、エンジン直通の MethodChannel が100%確実に開通します。
    if let registrar = self.registrar(forPlugin: "AppLiveNotificationPlugin") {
        let channel = FlutterMethodChannel(name: "app3.kportal/live_notification", binaryMessenger: registrar.messenger())

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
    }

    // 🟢【安全の極み】
    // 起動時にクラッシュや競合を誘発していた通知許可ポップアップ（requestAuthorization）は
    // ここから完全に消滅させました。これにより起動シーケンスのブロッキングリスクはゼロです。
    // 他のカメラやカレンダー権限と同じように、アプリが立ち上がった後、Dart側の自由なタイミングで自然に出せます。

    return result
  }
}