import SafariServices
import Foundation

class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let sharedDefaults = UserDefaults(suiteName: "group.com.h.k.portal")

        // 受信データを書き込み
        let dummyData = "TEST_SESSION_COOKIE_SUCCESS_12345"
        sharedDefaults?.set(dummyData, forKey: "session_cookie")
        sharedDefaults?.synchronize()

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["status": "ok"]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
