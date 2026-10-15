const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

function setupBanner() {
  let banner = document.getElementById('kdot-extension-banner');
  if (!banner) {
    banner = document.createElement('div');
    banner.id = 'kdot-extension-banner';
    banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:6px;box-shadow:0 2px 5px rgba(0,0,0,0.3);';
    banner.innerHTML = '🟡 K.dot 拡張機能動作中... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
    if (document.body) {
      document.body.appendChild(banner);
    } else {
      document.addEventListener('DOMContentLoaded', () => {
        if (document.body) document.body.appendChild(banner);
      });
    }
  }
  return banner;
}

function checkAndSyncCookie() {
  try {
    const banner = setupBanner();

    if (banner && banner.dataset.synced === "true") {
      return;
    }

    // 未ログイン状態（パスキー入力画面等）の場合
    if (window.location.href.includes('/login') || window.location.href.includes('/saml')) {
      if (banner) {
        banner.innerHTML = '🟡 K.dot 拡張機能動作中 (パスキー認証を行ってください) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
      }
      return;
    }

    // ログイン済み状態（すでにSafariでログイン済みの場合も含む）
    const docCookie = document.cookie || "";

    extAPI.runtime.sendMessage({ action: "SYNC_COOKIE", fallbackCookie: docCookie }, (response) => {
      if (!banner) return;

      const lastErr = extAPI.runtime ? extAPI.runtime.lastError : null;
      if (lastErr) {
        banner.innerHTML = '🔴 通信エラー: ' + lastErr.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
        return;
      }

      if (response && response.status === "success") {
        banner.dataset.synced = "true";
        banner.innerHTML = '🟢 既存セッション同期完了！アプリへ自動復帰中...';

        // 🟢 0.2秒で即座にアプリへ自動復帰！
        setTimeout(() => {
          window.location.href = "app3kportal://login-success";
        }, 200);
      } else {
        const reason = (response && response.reason) ? response.reason : "待機中";
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
checkAndSyncCookie();
setInterval(checkAndSyncCookie, 1000);
