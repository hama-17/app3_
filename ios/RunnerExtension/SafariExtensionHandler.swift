import SafariServices
import Foundation

class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo as? [String: Any] else {
            sendResponse(context: context, status: "error", reason: "no_user_info")
            return
        }

        var tokenStr: String? = nil
        if let message = userInfo[SFExtensionMessageKey] as? [String: Any] {
            tokenStr = (message["token"] as? String) ?? (message["cookie"] as? String)
        } else if let token = (userInfo["token"] as? String) ?? (userInfo["cookie"] as? String) {
            tokenStr = token
        }

        guard let token = tokenStr, !token.isEmpty else {
            sendResponse(context: context, status: "error", reason: "payload_empty")
            return
        }

        if let sharedDefaults = UserDefaults(suiteName: "group.com.h.k.portal") {
            sharedDefaults.set(token, forKey: "session_cookie")
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
