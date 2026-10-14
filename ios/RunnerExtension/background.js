browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  // ページの読み込み完了かつ lms.keio.jp に居るか判定
  if (changeInfo.status === 'complete' && tab.url && tab.url.includes('lms.keio.jp')) {

    // lms.keio.jp の Cookie をすべて取得
    browser.cookies.getAll({ url: "https://lms.keio.jp" }, (cookies) => {
      if (cookies && cookies.length > 0) {
        const cookieHeader = cookies.map(c => `${c.name}=${c.value}`).join('; ');

        // Native (SafariExtensionHandler.swift) へ Cookie を送信
        browser.runtime.sendNativeMessage("application.id", { "cookie": cookieHeader }, (response) => {
          // App Group への書き込み完了後、アプリへリダイレクトして復帰
          setTimeout(() => {
            browser.tabs.update(tabId, { url: "app3kportal://login-success" });
          }, 300);
        });
      }
    });
  }
});