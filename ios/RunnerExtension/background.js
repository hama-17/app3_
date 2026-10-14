browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.url && tab.url.includes('lms.keio.jp')) {

    // ログイン認証中の画面（auth/login/saml）はスキップ
    if (tab.url.includes('/login') || tab.url.includes('/saml') || tab.url.includes('auth')) {
      return;
    }

    browser.cookies.getAll({ url: "https://lms.keio.jp" }, (cookies) => {
      if (cookies && cookies.length > 0) {
        const cookieHeader = cookies.map(c => `${c.name}=${c.value}`).join('; ');

        // 🟢 第一引数にダミー文字列を渡さず、直接メッセージオブジェクトを送信
        browser.runtime.sendNativeMessage({ "cookie": cookieHeader }, (response) => {
          // Swift（App Group）への保存完了後、content.js へアプリ復帰を命令
          browser.tabs.sendMessage(tabId, { action: "REDIRECT_TO_APP" }).catch((err) => {
            console.log("SendMessage error: ", err);
          });
        });
      }
    });
  }
});