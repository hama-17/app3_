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
      respondOnce({ status: "error", reason: "BGタイムアウト(2.5s)" });
    }, 2500);

    try {
      // 🟢 URL・ドメインの両面からクッキーを全集計（HttpOnly含む）
      extAPI.cookies.getAll({ domain: "lms.keio.jp" }, (cookiesByDomain) => {
        extAPI.cookies.getAll({ url: "https://lms.keio.jp/" }, (cookiesByUrl) => {
          let cookieMap = new Map();

          if (cookiesByDomain) {
            cookiesByDomain.forEach(c => { if(c && c.name) cookieMap.set(c.name, c.value); });
          }
          if (cookiesByUrl) {
            cookiesByUrl.forEach(c => { if(c && c.name) cookieMap.set(c.name, c.value); });
          }
          if (message.fallbackCookie) {
            message.fallbackCookie.split(';').forEach(pair => {
              const parts = pair.split('=');
              if (parts.length >= 2) {
                const k = parts[0].trim();
                const v = parts.slice(1).join('=').trim();
                if (k && !cookieMap.has(k)) cookieMap.set(k, v);
              }
            });
          }

          let cookiePairs = [];
          cookieMap.forEach((v, k) => cookiePairs.push(`${k}=${v}`));
          const fullCookie = cookiePairs.join('; ');

          // 🟢 ログインセッションの存在判定（Canvasの主要セッションキーまたは全クッキー長で判定）
          if (!fullCookie || fullCookie.trim().length < 10) {
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
      });
    } catch (e) {
      respondOnce({ status: "error", reason: "BG例外: " + e.message });
    }
    return true;
  }
});
