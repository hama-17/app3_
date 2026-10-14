import SafariServices

class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem else { return }

        let response = NSExtensionItem()
        response.userInfo = [ SFExtensionMessageKey: [ "Response": "Cookie synced successfully" ] ]

        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}