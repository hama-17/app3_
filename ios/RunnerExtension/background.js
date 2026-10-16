const extAPI = (typeof browser !== 'undefined') ? browser : chrome;
const NATIVE_APP_ID = "com.h.k.portal.extension";

extAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "SYNC_TOKEN") {
    const token = message.token;
    if (!token) {
      sendResponse({ status: "error", reason: "Token Empty" });
      return true;
    }

    extAPI.runtime.sendNativeMessage(NATIVE_APP_ID, { "token": token }, (response) => {
      const err = extAPI.runtime ? extAPI.runtime.lastError : null;
      if (err) {
        sendResponse({ status: "error", reason: "Native Err: " + err.message });
      } else if (response && response.status === "success") {
        sendResponse({ status: "success", tokenLength: token.length });
      } else {
        const errDetail = (response && response.reason) ? response.reason : "Native Sync Fail";
        sendResponse({ status: "error", reason: errDetail });
      }
    });

    return true;
  }
});
