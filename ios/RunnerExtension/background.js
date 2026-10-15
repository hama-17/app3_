const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

extAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "SYNC_COOKIE") {
    try {
      extAPI.cookies.getAll({ url: "https://lms.keio.jp/" }, (cookies) => {
        let cookiePairs = [];

        if (cookies && cookies.length > 0) {
          cookies.forEach(c => {
            if (c && c.name && c.value) {
              cookiePairs.push(`${c.name}=${c.value}`);
            }
          });
        }

        if (message.fallbackCookie) {
          message.fallbackCookie.split(';').forEach(pair => {
            const p = pair.trim();
            if (p && !cookiePairs.includes(p)) {
              cookiePairs.push(p);
            }
          });
        }

        const fullCookie = cookiePairs.join('; ');

        if (!fullCookie || fullCookie.trim().length < 5) {
          sendResponse({ status: "error", reason: "No Cookie Found" });
          return;
        }

        // 🟢 Native Swift へクッキー送信（iOS Safari のレスポンス遅延を待たずに即時成功を返す！）
        try {
          extAPI.runtime.sendNativeMessage("application.id", { "cookie": fullCookie });
        } catch (nativeErr) {
          console.log("sendNativeMessage error:", nativeErr);
        }

        // Swift 側への書き込みは数ミリ秒で完了するため、待たずに即時レスポンス
        sendResponse({ status: "success", cookieLength: fullCookie.length });
      });
    } catch (e) {
      sendResponse({ status: "error", reason: "BG Exception: " + e.message });
    }
    return true;
  }
});
