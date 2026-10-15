const extAPI = (typeof browser !== 'undefined') ? browser : chrome;
let isSyncing = false;

function setupBanner() {
  let banner = document.getElementById('kdot-extension-banner');
  if (!banner) {
    banner = document.createElement('div');
    banner.id = 'kdot-extension-banner';
    banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:6px;box-shadow:0 2px 5px rgba(0,0,0,0.3);';
    banner.innerHTML = '🟡 K.dot Extension Working... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
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
  if (isSyncing) return;

  try {
    const banner = setupBanner();

    if (banner && banner.dataset.synced === "true") {
      return;
    }

    if (window.location.href.includes('/login') || window.location.href.includes('/saml')) {
      if (banner) {
        banner.innerHTML = '🟡 K.dot 拡張機能動作中 (パスキー認証を完了させてください) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
      }
      return;
    }

    isSyncing = true;
    const docCookie = document.cookie || "";

    if (banner && !banner.dataset.synced) {
      banner.innerHTML = '🟡 Cookie確認中... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
    }

    const lockTimer = setTimeout(() => {
      if (isSyncing) isSyncing = false;
    }, 3000);

    extAPI.runtime.sendMessage({ action: "SYNC_COOKIE", fallbackCookie: docCookie }, (response) => {
      clearTimeout(lockTimer);
      isSyncing = false;
      if (!banner) return;

      const lastErr = extAPI.runtime ? extAPI.runtime.lastError : null;
      if (lastErr) {
        banner.innerHTML = '🔴 Comm Error: ' + lastErr.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
        return;
      }

      if (response && response.status === "success") {
        banner.dataset.synced = "true";
        banner.innerHTML = '🟢 認証セッション同期成功 (' + response.cookieLength + '文字)! アプリへ自動復帰中...';
        setTimeout(() => {
          window.location.href = "app3kportal://login-success";
        }, 300);
      } else {
        const reason = (response && response.reason) ? response.reason : "待機中";
        banner.innerHTML = '🟡 同期待機中 (' + reason + ') ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
      }
    });
  } catch (err) {
    isSyncing = false;
    const banner = document.getElementById('kdot-extension-banner');
    if (banner) {
      banner.innerHTML = '🔴 JS Exception: ' + err.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
    }
  }
}

setupBanner();
checkAndSyncCookie();
setInterval(checkAndSyncCookie, 1500);
