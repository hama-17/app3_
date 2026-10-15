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
      const currentTabUrl = (sender && sender.tab && sender.tab.url) ? sender.tab.url : "https://lms.keio.jp/";
      let cookieMap = new Map();

      // 1. アクティブタブのURLから直接 HttpOnly クッキーを取得
      extAPI.cookies.getAll({ url: currentTabUrl }, (cookiesTab) => {
        if (cookiesTab) {
          cookiesTab.forEach(c => {
            if (c && c.name && c.value) cookieMap.set(c.name, c.value);
          });
        }

        // 2. LMSルートURLからも相乗取得
        extAPI.cookies.getAll({ url: "https://lms.keio.jp/" }, (cookiesRoot) => {
          if (cookiesRoot) {
            cookiesRoot.forEach(c => {
              if (c && c.name && c.value) cookieMap.set(c.name, c.value);
            });
          }

          // 3. fallback (document.cookie)
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
          let detectedNames = [];
          let hasCanvasSession = false;

          cookieMap.forEach((v, k) => {
            cookiePairs.push(`${k}=${v}`);
            detectedNames.push(k);
            if (k.includes('canvas_session')) {
              hasCanvasSession = true;
            }
          });

          const fullCookie = cookiePairs.join('; ');
          const namesSummary = detectedNames.length > 0 ? detectedNames.join(',') : 'なし';

          // 🟢 _canvas_session が見つからない、または 200 文字未満の場合は一切送信しない（古いデータの誤書き込み防止）
          if (!hasCanvasSession || fullCookie.length < 200) {
            safeResponse({ status: "error", reason: `ログイン完了待ち (検出:[${namesSummary}] / 長さ:${fullCookie.length}文字)` });
            return;
          }

          sendToNative(fullCookie, safeResponse);
        });
      });
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
