browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.url && tab.url.includes('lms.keio.jp')) {
    // ログイン途中の画面（auth / login / saml）ではスキップ
    if (tab.url.includes('/login') || tab.url.includes('/saml') || tab.url.includes('auth')) {
      return;
    }

    browser.cookies.getAll({ url: "https://lms.keio.jp" }, (cookies) => {
      if (cookies && cookies.length > 0) {
        // セッションCookie（ログイン完了を示すCookie）が存在するか判定
        const hasSessionCookie = cookies.some(c =>
          c.name.includes('session') || c.name.includes('canvas') || c.name.includes('_legacy')
        );

        if (hasSessionCookie) {
          const cookieHeader = cookies.map(c => `${c.name}=${c.value}`).join('; ');
          browser.runtime.sendNativeMessage("application.id", { "cookie": cookieHeader }, (response) => {
            browser.tabs.sendMessage(tabId, { action: "REDIRECT_TO_APP" }).catch((err) => {
              console.log("Redirect message failed: ", err);
            });
          });
        }
      }
    });
  }
});
