import SafariServices

class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo,
              let message = userInfo[SFExtensionMessageKey] as? [String: Any],
              let cookie = message["cookie"] as? String else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        // 🟢 AppDelegate.swift と同じ App Group ID を指定
        if let defaults = UserDefaults(suiteName: "group.com.h.k.portal") {
            defaults.set(cookie, forKey: "session_cookie")
            defaults.synchronize()
        }

        context.completeRequest(returningItems: nil, completionHandler: nil)
    }
}