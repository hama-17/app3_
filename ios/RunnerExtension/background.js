browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  // ページ読み込み完了、かつ lms.keio.jp に到達しているか確認
  if (changeInfo.status === 'complete' && tab.url && tab.url.includes('lms.keio.jp')) {

    // lms.keio.jp の Cookie を取得
    browser.cookies.getAll({ url: "https://lms.keio.jp" }, (cookies) => {
      if (cookies && cookies.length > 0) {
        const cookieHeader = cookies.map(c => `${c.name}=${c.value}`).join('; ');

        // Native (SafariExtensionHandler.swift) へ Cookie 送信
        browser.runtime.sendNativeMessage("application.id", { "cookie": cookieHeader }, (response) => {
          // 🟢 成功後、アプリへ自動切り替え（ディープリンク起動）
          setTimeout(() => {
            browser.tabs.update(tabId, { url: "app3kportal://login-success" });
          }, 300);
        });
      }
    });
  }
});