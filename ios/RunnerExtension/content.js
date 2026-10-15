function setupBanner() {
  if (!document.getElementById('kdot-extension-banner')) {
    const banner = document.createElement('div');
    banner.id = 'kdot-extension-banner';
    banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:6px;box-shadow:0 2px 5px rgba(0,0,0,0.3);';
    banner.innerHTML = 'K.dot 拡張機能初期化中...';
    document.body.appendChild(banner);
  }
}

function checkAndSyncCookie() {
  setupBanner();
  const banner = document.getElementById('kdot-extension-banner');
  const cookie = document.cookie;

  if (cookie && cookie.length > 10 && !window.location.href.includes('/login') && !window.location.href.includes('/saml')) {
    if (banner && !banner.dataset.synced) {
      banner.innerHTML = 'Cookie検出 (' + cookie.length + '文字) 送信中... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;font-weight:bold;">[アプリへ戻る]</a>';
    }

    browser.runtime.sendMessage({ action: "SYNC_COOKIE", cookie: cookie }).then((response) => {
      if (banner) {
        banner.dataset.synced = "true";
        banner.innerHTML = '🟢 App Groupへ送信完了！ ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;font-weight:bold;text-decoration:underline;">[タップしてアプリへ戻る]</a>';
      }
    }).catch((e) => {
      if (banner && !banner.dataset.synced) {
        banner.innerHTML = '🔴 送信エラー: ' + e.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
      }
    });
  } else {
    if (banner && !banner.dataset.synced) {
      banner.innerHTML = '🟡 K.dot 拡張機能動作中 (Cookie未検出・ログイン待ち) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
    }
  }
}

setupBanner();
setInterval(checkAndSyncCookie, 1500);
