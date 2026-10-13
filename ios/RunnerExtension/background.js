browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  // ログイン完了後のページURLを検知
  if (changeInfo.status === 'complete' && tab.url && (tab.url.includes('/dashboard') || tab.url.includes('/home'))) {

    // browser.cookies API を使って HttpOnly を含む全クッキーを取得
    browser.cookies.getAll({ url: tab.url }, (cookies) => {
      if (cookies && cookies.length > 0) {
        // "name=value; name2=value2" のクッキー文字列を生成
        const cookieHeader = cookies.map(c => `${c.name}=${c.value}`).join('; ');

        // Swift (SafariExtensionHandler) へ送信
        browser.runtime.sendNativeMessage("application.id", { "cookie": cookieHeader });

        // アプリへ自動復帰（ディープリンク）
        browser.tabs.update(tabId, { url: "app3kportal://login-success" });
      }
    });
  }
});