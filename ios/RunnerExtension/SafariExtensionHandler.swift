import SafariServices
import UIKit

class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo,
              let message = userInfo[SFExtensionMessageKey] as? [String: Any],
              let cookie = message["cookie"] as? String else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        // App Group にクッキーを保存
        if let defaults = UserDefaults(suiteName: "group.com.h.k.portal") {
            defaults.set(cookie, forKey: "session_cookie")
            defaults.synchronize()
        }

        // 🟢 ディープリンクでアプリを自動起動
        if let url = URL(string: "app3kportal://login-success") {
            var responder: UIResponder? = self
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                    break
                }
                responder = responder?.next
            }
        }

        context.completeRequest(returningItems: nil, completionHandler: nil)
    }
}