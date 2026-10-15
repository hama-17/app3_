const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

extAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "SYNC_COOKIE") {
    let responded = false;

    const safeResponse = (data) => {
      if (!responded) {
        responded = true;
        clearTimeout(timer);
        try { sendResponse(data); } catch(e) {}
      }
    };

    const timer = setTimeout(() => {
      safeResponse({ status: "error", reason: "BG Timeout (3s)" });
    }, 3000);

    try {
      if (extAPI.cookies && extAPI.cookies.getAll) {
        extAPI.cookies.getAll({}, (allCookies) => {
          const count = allCookies ? allCookies.length : 0;

          if (count === 0) {
            safeResponse({ status: "error", reason: "Cookie API件数:0 (iOS設定>Safari>拡張機能のWeb許可を確認)" });
            return;
          }

          let cookieMap = new Map();
          allCookies.forEach(c => {
            if (c && c.domain && c.domain.includes('keio.jp') && c.name && c.value) {
              cookieMap.set(c.name, c.value);
            }
          });

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
          let hasCanvasSession = false;

          cookieMap.forEach((v, k) => {
            cookiePairs.push(`${k}=${v}`);
            if (k.toLowerCase().includes('canvas_session')) {
              hasCanvasSession = true;
            }
          });

          const fullCookie = cookiePairs.join('; ');

          if (!hasCanvasSession || fullCookie.length < 250) {
            safeResponse({ status: "error", reason: `検出:${cookieMap.size}個 / Len:${fullCookie.length} (ログイン完了待ち)` });
            return;
          }

          sendToNative(fullCookie, safeResponse);
        });
      } else {
        safeResponse({ status: "error", reason: "Cookie API非対応" });
      }
    } catch (e) {
      safeResponse({ status: "error", reason: "BG Exception: " + e.message });
    }

    return true;
  }
});

function sendToNative(cookieString, safeResponse) {
  try {
    const extAPI = (typeof browser !== 'undefined') ? browser : chrome;
    extAPI.runtime.sendNativeMessage("application.id", { "cookie": cookieString }, (response) => {
      const err = extAPI.runtime ? extAPI.runtime.lastError : null;
      if (err) {
        safeResponse({ status: "error", reason: "Native Err: " + err.message });
      } else if (response && response.status === "success") {
        safeResponse({ status: "success", cookieLength: cookieString.length });
      } else {
        const errDetail = (response && response.reason) ? response.reason : "Native Sync Fail";
        safeResponse({ status: "error", reason: errDetail });
      }
    });
  } catch (e) {
    safeResponse({ status: "error", reason: "Native Exception: " + e.message });
  }
}
