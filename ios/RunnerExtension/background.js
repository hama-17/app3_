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

      // 1. fallback (document.cookie) からの仮データ
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

      // 2. 🟢 パラメータ指定なしで Safari の全 Cookie を一括取得（iOS Safari の URL フィルターバグを回避）
      if (extAPI.cookies && extAPI.cookies.getAll) {
        extAPI.cookies.getAll({}, (allCookies) => {
          if (allCookies && allCookies.length > 0) {
            allCookies.forEach(c => {
              if (c && c.name && c.value) {
                const dom = (c.domain || "").toLowerCase();
                // keio.jp 関連ドメインの全クッキー（_canvas_session 含む）を自前で抽出
                if (dom.includes('keio.jp') || dom.includes('lms.keio') || dom === '') {
                  cookieMap.set(c.name, c.value);
                }
              }
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
          const namesSummary = detectedNames.length > 0 ? detectedNames.join(',') : 'なし';

          // 🟢 本物の _canvas_session または 180 文字以上の認証クッキー群が揃った場合のみ送信
          if ((!hasCanvasSession && cookieMap.size < 2) || fullCookie.length < 180) {
            safeResponse({ status: "error", reason: `ログイン完了待ち (検出:[${namesSummary}] / 長さ:${fullCookie.length}文字)` });
            return;
          }

          sendToNative(fullCookie, safeResponse);
        });
      } else {
        safeResponse({ status: "error", reason: "Cookie API 非対応" });
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
