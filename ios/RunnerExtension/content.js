const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

function setupBanner() {
  if (!document.getElementById('kdot-extension-banner')) {
    const banner = document.createElement('div');
    banner.id = 'kdot-extension-banner';
    banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:6px;box-shadow:0 2px 5px rgba(0,0,0,0.3);';
    banner.innerHTML = 'K.dot 拡張機能初期化中...';
    if (document.body) {
      document.body.appendChild(banner);
    } else {
      document.addEventListener('DOMContentLoaded', () => {
        if (document.body) document.body.appendChild(banner);
      });
    }
  }
}

function checkAndSyncCookie() {
  try {
    setupBanner();
    const banner = document.getElementById('kdot-extension-banner');

    if (window.location.href.includes('/login') || window.location.href.includes('/saml')) {
      if (banner) {
        banner.innerHTML = '🟡 K.dot 拡張機能動作中 (パスキー認証を行ってください) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
      }
      return;
    }

    const docCookie = document.cookie || "";

    extAPI.runtime.sendMessage({ action: "SYNC_COOKIE", fallbackCookie: docCookie }, (response) => {
      if (!banner) return;

      const lastErr = extAPI.runtime.lastError;
      if (lastErr) {
        banner.innerHTML = '🔴 通信エラー: ' + lastErr.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
        return;
      }

      if (response && response.status === "success") {
        banner.dataset.synced = "true";
        banner.innerHTML = '🟢 App Groupへ送信完了！ (' + response.cookieLength + '文字) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;font-weight:bold;text-decoration:underline;">[タップしてアプリへ戻る]</a>';
      } else {
        const reason = (response && response.reason) ? response.reason : "処理中...";
        banner.innerHTML = '🟡 同期待機中 (' + reason + ') ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
      }
    });
  } catch (err) {
    const banner = document.getElementById('kdot-extension-banner');
    if (banner) {
      banner.innerHTML = '🔴 JS例外: ' + err.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
    }
  }
}

setupBanner();
setInterval(checkAndSyncCookie, 2000);
