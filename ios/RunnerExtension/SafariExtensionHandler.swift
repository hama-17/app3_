import SafariServices
import Foundation

class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo as? [String: Any],
              let message = userInfo[SFExtensionMessageKey] as? [String: Any],
              let cookie = message["cookie"] as? String else {
            let response = NSExtensionItem()
            response.userInfo = [ SFExtensionMessageKey: [ "status": "error", "reason": "invalid_payload" ] ]
            context.completeRequest(returningItems: [response], completionHandler: nil)
            return
        }

        if let sharedDefaults = UserDefaults(suiteName: "group.com.h.k.portal") {
            sharedDefaults.set(cookie, forKey: "session_cookie")
            sharedDefaults.synchronize()

            let response = NSExtensionItem()
            response.userInfo = [ SFExtensionMessageKey: [ "status": "success" ] ]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        } else {
            let response = NSExtensionItem()
            response.userInfo = [ SFExtensionMessageKey: [ "status": "error", "reason": "no_app_group" ] ]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }
}
