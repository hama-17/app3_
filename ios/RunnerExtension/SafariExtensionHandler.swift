import SafariServices
import Foundation

class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo as? [String: Any] else {
            sendResponse(context: context, status: "error", reason: "no_user_info")
            return
        }

        var cookieStr: String? = nil
        if let message = userInfo[SFExtensionMessageKey] as? [String: Any] {
            cookieStr = message["cookie"] as? String
        } else if let cookie = userInfo["cookie"] as? String {
            cookieStr = cookie
        }

        guard let cookie = cookieStr, !cookie.isEmpty else {
            sendResponse(context: context, status: "error", reason: "payload_empty")
            return
        }

        if let sharedDefaults = UserDefaults(suiteName: "group.com.h.k.portal") {
            sharedDefaults.set(cookie, forKey: "session_cookie")
            sharedDefaults.synchronize()
            sendResponse(context: context, status: "success", reason: nil)
        } else {
            sendResponse(context: context, status: "error", reason: "no_app_group")
        }
    }

    private func sendResponse(context: NSExtensionContext, status: String, reason: String?) {
        let response = NSExtensionItem()
        var resDict: [String: Any] = ["status": status]
        if let reason = reason {
            resDict["reason"] = reason
        }
        response.userInfo = [SFExtensionMessageKey: resDict]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
