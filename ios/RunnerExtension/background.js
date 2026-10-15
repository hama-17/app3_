const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

extAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "SYNC_COOKIE") {
    try {
      // 全パス・全ドメインのクッキーを全網羅検索
      extAPI.cookies.getAll({ domain: "lms.keio.jp" }, (cookies) => {
        let cookieMap = new Map();

        if (cookies && cookies.length > 0) {
          cookies.forEach(c => {
            if (c && c.name && c.value) {
              cookieMap.set(c.name, c.value);
            }
          });
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

        if (!fullCookie || fullCookie.trim().length < 10) {
          sendResponse({ status: "error", reason: "Cookie Not Found (Please Login)" });
          return;
        }

        extAPI.runtime.sendNativeMessage("application.id", { "cookie": fullCookie }, (response) => {
          const lastErr = extAPI.runtime ? extAPI.runtime.lastError : null;
          if (lastErr) {
            sendResponse({ status: "error", reason: "Native Err: " + lastErr.message });
          } else if (response && response.status === "success") {
            sendResponse({ status: "success", cookieLength: fullCookie.length });
          } else {
            const errDetail = (response && response.reason) ? response.reason : "Native Sync Fail";
            sendResponse({ status: "error", reason: errDetail });
          }
        });
      });
    } catch (e) {
      sendResponse({ status: "error", reason: "BG Exception: " + e.message });
    }
    return true;
  }
});
