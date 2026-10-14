browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.url && tab.url.includes('lms.keio.jp')) {

    // lms.keio.jp の Cookie を取得
    browser.cookies.getAll({ url: "https://lms.keio.jp" }, (cookies) => {
      if (cookies && cookies.length > 0) {
        const cookieHeader = cookies.map(c => `${c.name}=${c.value}`).join('; ');

        // Native (SafariExtensionHandler.swift) へ Cookie 送信
        browser.runtime.sendNativeMessage("application.id", { "cookie": cookieHeader }, (response) => {
          // content.js へメッセージを送ってアプリへ安全に回帰させる
          browser.tabs.sendMessage(tabId, { action: "REDIRECT_TO_APP" }).catch((err) => {
            console.log("Message error, fallback to direct location: ", err);
          });
        });
      }
    });
  }
});