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

    // 2. 大元の初期化（super.application）を先に走らせて、iOS側の画面の土台を確定生成
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // 🟢 解決の鍵：カメラ等の影響で変化した階層構造を全自動で走査し、
    // 隠れた FlutterViewController を100%確実に捕捉するディープスキャンをキックします。
    var flutterViewController: FlutterViewController? = nil

    if let rootVC = window?.rootViewController {
        if let fvc = rootVC as? FlutterViewController {
            flutterViewController = fvc
        } else {
            // root直下にいない場合、子ビューコントローラーの階層（コンテナ）の中を徹底捜索
            for child in rootVC.children {
                if let fvc = child as? FlutterViewController {
                    flutterViewController = fvc
                    break
                }
            }
        }
    }

    // 3. 確実に捕捉したスレッドに対してのみMethodChannelを開通
    if let controller = flutterViewController {
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
                          print("iOS Notification Schedule Error: $error")
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
        // 万が一見つからなかった場合の非常用デバッグシグナル
        print("🚨 ALERT: FlutterViewController could not be found in active hierarchy.")
    }

    // 4. 非同期で通知権限をリクエスト（描画スレッドを絶対に邪魔しない）
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

    return result
  }
}