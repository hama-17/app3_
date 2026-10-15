browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "SYNC_COOKIE") {
    // 末尾スラッシュ付き URL で取得
    browser.cookies.getAll({ url: "https://lms.keio.jp/" }, (cookies) => {
      let cookieParts = [];
      if (cookies && cookies.length > 0) {
        cookieParts.push(cookies.map(c => `${c.name}=${c.value}`).join('; '));
      }
      if (message.fallbackCookie && message.fallbackCookie.length > 0) {
        cookieParts.push(message.fallbackCookie);
      }

      const fullCookie = cookieParts.join('; ');

      if (!fullCookie || fullCookie.trim().length === 0) {
        sendResponse({ status: "error", reason: "Cookie未検出(ログイン完了待ち)" });
        return;
      }

      browser.runtime.sendNativeMessage("application.id", { "cookie": fullCookie }, (response) => {
        if (browser.runtime.lastError) {
          sendResponse({ status: "error", reason: "Native通信失敗: " + browser.runtime.lastError.message });
        } else if (response && response.status === "success") {
          sendResponse({ status: "success", cookieLength: fullCookie.length });
        } else {
          const errDetail = (response && response.reason) ? response.reason : "Native書き込み失敗";
          sendResponse({ status: "error", reason: errDetail });
        }
      });
    });
    return true; // 非同期応答を有効化
  }
});
