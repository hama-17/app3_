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
      let cookieMap = new Map();

      // 1. fallback (document.cookie)
      if (message.fallbackCookie) {
        message.fallbackCookie.split(';').forEach(pair => {
          const parts = pair.split('=');
          if (parts.length >= 2) {
            const k = parts[0].trim();
            const v = parts.slice(1).join('=').trim();
            if (k) cookieMap.set(k, v);
          }
        });
      }

      // 2. 🟢 sender.tab から cookieStoreId と url を取得してアクティブタブの Cookie 領域を狙い撃ち
      const tabStoreId = (sender && sender.tab && sender.tab.cookieStoreId) ? sender.tab.cookieStoreId : null;
      const tabUrl = (sender && sender.tab && sender.tab.url) ? sender.tab.url : "https://lms.keio.jp/";

      const queryOptions = {};
      if (tabStoreId) queryOptions.storeId = tabStoreId;

      if (extAPI.cookies && extAPI.cookies.getAll) {
        extAPI.cookies.getAll(queryOptions, (allCookies) => {
          if (allCookies && allCookies.length > 0) {
            allCookies.forEach(c => {
              if (c && c.name && c.value) {
                cookieMap.set(c.name, c.value);
              }
            });
          }

          // タブURL直接指定でも念押し検索
          extAPI.cookies.getAll({ url: tabUrl, ...(tabStoreId ? { storeId: tabStoreId } : {}) }, (urlCookies) => {
            if (urlCookies && urlCookies.length > 0) {
              urlCookies.forEach(c => {
                if (c && c.name && c.value) cookieMap.set(c.name, c.value);
              });
            }

            let cookiePairs = [];
            let detectedNames = [];
            let hasCanvasSession = false;

            cookieMap.forEach((v, k) => {
              cookiePairs.push(`${k}=${v}`);
              detectedNames.push(k);
              if (k.toLowerCase().includes('canvas_session')) {
                hasCanvasSession = true;
              }
            });

            const fullCookie = cookiePairs.join('; ');
            const namesSummary = detectedNames.length > 0 ? detectedNames.join(',') : 'None';

            // 🟢 本物の _canvas_session が存在し、180文字以上ある場合のみ送信
            if (!hasCanvasSession || fullCookie.length < 180) {
              safeResponse({ status: "error", reason: `Waiting Login (Keys:[${namesSummary}], Len:${fullCookie.length})` });
              return;
            }

            sendToNative(fullCookie, safeResponse);
          });
        });
      } else {
        safeResponse({ status: "error", reason: "Cookie API Not Supported" });
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
