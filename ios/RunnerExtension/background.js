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

      const evaluateAndSend = (extraCookies) => {
        if (extraCookies && extraCookies.length > 0) {
          extraCookies.forEach(c => {
            if (c && c.name && c.value) {
              cookieMap.set(c.name, c.value);
            }
          });
        }

        let cookiePairs = [];
        let detectedKeys = [];
        let hasCanvasSession = false;

        cookieMap.forEach((v, k) => {
          cookiePairs.push(`${k}=${v}`);
          detectedKeys.push(k);

          const lowerK = k.toLowerCase();
          if (lowerK.includes('canvas_session')) {
            hasCanvasSession = true;
          }
        });

        const fullCookie = cookiePairs.join('; ');

        // 🟢 本物の _canvas_session が存在し、かつ 250 文字以上ある場合のみ送信許可
        if (!hasCanvasSession || fullCookie.length < 250) {
          const keyList = detectedKeys.length > 0 ? detectedKeys.join(', ') : "なし";
          safeResponse({ status: "error", reason: `ログイン完了待ち (検出キー: [${keyList}] / 長さ: ${fullCookie.length}文字)` });
          return;
        }

        sendToNative(fullCookie, safeResponse);
      };

      // 🟢 ドメイン制限なしで全クッキーを取得
      if (extAPI.cookies && extAPI.cookies.getAll) {
        extAPI.cookies.getAll({}, (allCookies) => {
          let filtered = [];
          if (allCookies && allCookies.length > 0) {
            filtered = allCookies.filter(c => c && c.domain && c.domain.includes('keio.jp'));
          }
          evaluateAndSend(filtered);
        });
      } else {
        evaluateAndSend([]);
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
