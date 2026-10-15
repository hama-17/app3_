browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "SYNC_COOKIE") {
    browser.cookies.getAll({ url: "https://lms.keio.jp" }, (cookies) => {
      if (!cookies || cookies.length === 0) {
        sendResponse({ status: "error", reason: "クッキーなし (ログインしてください)" });
        return;
      }

      const cookieHeader = cookies.map(c => `${c.name}=${c.value}`).join('; ');

      browser.runtime.sendNativeMessage("application.id", { "cookie": cookieHeader }, (response) => {
        if (browser.runtime.lastError) {
          sendResponse({ status: "error", reason: browser.runtime.lastError.message });
        } else if (response && response.status === "success") {
          sendResponse({ status: "success", cookieLength: cookieHeader.length });
        } else {
          const errDetail = (response && response.reason) ? response.reason : "Nativeエラー";
          sendResponse({ status: "error", reason: errDetail });
        }
      });
    });
    return true; // 非同期応答のために必須
  }
});
