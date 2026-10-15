console.log("K.dot background script initialized.");

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "SYNC_COOKIE" && message.cookie) {
    browser.runtime.sendNativeMessage("application.id", { "cookie": message.cookie }, (response) => {
      console.log("Native response:", response);
    });
    return Promise.resolve({ status: "ok" });
  }
});
