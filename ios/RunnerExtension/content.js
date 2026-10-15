const extAPI = (typeof browser !== 'undefined') ? browser : chrome;
let isSyncing = false;

function setupBanner() {
  let banner = document.getElementById('kdot-extension-banner');
  if (!banner) {
    banner = document.createElement('div');
    banner.id = 'kdot-extension-banner';
    banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:6px;box-shadow:0 2px 5px rgba(0,0,0,0.3);';
    banner.innerHTML = '🟡 K.dot Extension Working... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>';
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
        banner.innerHTML = '🟡 K.dot Extension (Please complete Passkey login) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>';
      }
      return;
    }

    isSyncing = true;
    const docCookie = document.cookie || "";

    if (banner && !banner.dataset.synced) {
      banner.innerHTML = '🟡 Extracting & Syncing Session... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>';
    }

    extAPI.runtime.sendMessage({ action: "SYNC_COOKIE", fallbackCookie: docCookie }, (response) => {
      isSyncing = false;
      if (!banner) return;

      const lastErr = extAPI.runtime ? extAPI.runtime.lastError : null;
      if (lastErr) {
        banner.innerHTML = '🔴 Comm Error: ' + lastErr.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>';
        return;
      }

      if (response && response.status === "success") {
        banner.dataset.synced = "true";
        banner.innerHTML = '🟢 App Group Sync Success (' + response.cookieLength + ' chars)! Returning to App...';
        setTimeout(() => {
          window.location.href = "app3kportal://login-success";
        }, 300);
      } else {
        const reason = (response && response.reason) ? response.reason : "Waiting";
        banner.innerHTML = '🟡 Sync Waiting (' + reason + ') ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>';
      }
    });
  } catch (err) {
    isSyncing = false;
    const banner = document.getElementById('kdot-extension-banner');
    if (banner) {
      banner.innerHTML = '🔴 JS Exception: ' + err.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>';
    }
  }
}

setupBanner();
checkAndSyncCookie();
setInterval(checkAndSyncCookie, 2000);
