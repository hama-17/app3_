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

      if (extAPI.cookies && extAPI.cookies.getAll) {
        extAPI.cookies.getAll({ domain: "lms.keio.jp" }, (cookiesByDomain) => {
          if (cookiesByDomain && cookiesByDomain.length > 0) {
            cookiesByDomain.forEach(c => {
              if (c && c.name && c.value) cookieMap.set(c.name, c.value);
            });
          }

          extAPI.cookies.getAll({ url: "https://lms.keio.jp/" }, (cookiesByUrl) => {
            if (cookiesByUrl && cookiesByUrl.length > 0) {
              cookiesByUrl.forEach(c => {
                if (c && c.name && c.value) cookieMap.set(c.name, c.value);
              });
            }

            let cookiePairs = [];
            cookieMap.forEach((v, k) => cookiePairs.push(`${k}=${v}`));
            const fullCookie = cookiePairs.join('; ');

            sendToNative(fullCookie, safeResponse);
          });
        });
      } else {
        let cookiePairs = [];
        cookieMap.forEach((v, k) => cookiePairs.push(`${k}=${v}`));
        const fullCookie = cookiePairs.join('; ');

        sendToNative(fullCookie, safeResponse);
      }
    } catch (e) {
      safeResponse({ status: "error", reason: "BG Exception: " + e.message });
    }

    return true;
  }
});

function sendToNative(cookieString, safeResponse) {
  if (!cookieString || cookieString.trim().length < 5) {
    safeResponse({ status: "error", reason: "No Cookie Found" });
    return;
  }

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
