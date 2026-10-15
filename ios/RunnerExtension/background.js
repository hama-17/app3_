const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

extAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "SYNC_COOKIE") {
    let hasResponded = false;

    const respondOnce = (data) => {
      if (!hasResponded) {
        hasResponded = true;
        clearTimeout(timeoutTimer);
        try { sendResponse(data); } catch(e) {}
      }
    };

    const timeoutTimer = setTimeout(() => {
      respondOnce({ status: "error", reason: "BG応答タイムアウト(3s)" });
    }, 3000);

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
          respondOnce({ status: "error", reason: "Cookie未検出(ログイン完了待ち)" });
          return;
        }

        extAPI.runtime.sendNativeMessage("application.id", { "cookie": fullCookie }, (response) => {
          const lastErr = extAPI.runtime ? extAPI.runtime.lastError : null;
          if (lastErr) {
            respondOnce({ status: "error", reason: "Native通信失敗: " + lastErr.message });
          } else if (response && response.status === "success") {
            respondOnce({ status: "success", cookieLength: fullCookie.length });
          } else {
            const errDetail = (response && response.reason) ? response.reason : "Native書き込み失敗";
            respondOnce({ status: "error", reason: errDetail });
          }
        });
      });
    } catch (e) {
      respondOnce({ status: "error", reason: "BG処理例外: " + e.message });
    }
    return true;
  }
});
