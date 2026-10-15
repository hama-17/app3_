const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

extAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "SYNC_COOKIE") {
    try {
      extAPI.cookies.getAll({ url: "https://lms.keio.jp/" }, (cookies) => {
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

        extAPI.runtime.sendNativeMessage("application.id", { "cookie": fullCookie }, (response) => {
          const lastErr = extAPI.runtime.lastError;
          if (lastErr) {
            sendResponse({ status: "error", reason: "Native通信失敗: " + lastErr.message });
          } else if (response && response.status === "success") {
            sendResponse({ status: "success", cookieLength: fullCookie.length });
          } else {
            const errDetail = (response && response.reason) ? response.reason : "Native書き込み失敗";
            sendResponse({ status: "error", reason: errDetail });
          }
        });
      });
    } catch (e) {
      sendResponse({ status: "error", reason: "BG処理例外: " + e.message });
    }
    return true;
  }
});
