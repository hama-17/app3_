const extAPI = (typeof browser !== 'undefined') ? browser : chrome;
let isExecuting = false;
let lastBannerText = "";

function updateBannerText(banner, text) {
  if (lastBannerText !== text) {
    lastBannerText = text;
    banner.innerHTML = text;
  }
}

function setupBanner() {
  let banner = document.getElementById('kdot-extension-banner');
  if (!banner) {
    banner = document.createElement('div');
    banner.id = 'kdot-extension-banner';
    banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:6px;box-shadow:0 2px 5px rgba(0,0,0,0.3);';
    updateBannerText(banner, '🟡 K.dot Extension Working... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
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

function extractCsrfToken() {
  const metaToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
                 || document.querySelector('meta[name="authenticity-token"]')?.getAttribute('content');
  if (metaToken) return metaToken;

  const cookies = document.cookie.split(';');
  for (let i = 0; i < cookies.length; i++) {
    const pair = cookies[i].trim().split('=');
    if (pair[0] === '_csrf_token' || pair[0] === 'csrf_token') {
      return decodeURIComponent(pair.slice(1).join('='));
    }
  }

  return null;
}

async function autoGenerateTokenAndSync() {
  if (isExecuting) return;

  try {
    const banner = setupBanner();

    if (banner && banner.dataset.synced === "true") {
      return;
    }

    if (window.location.href.includes('/login') || window.location.href.includes('/saml')) {
      if (banner) {
        updateBannerText(banner, '🟡 K.dot Extension (Please complete Passkey login) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
      }
      return;
    }

    isExecuting = true;
    if (banner && !banner.dataset.synced) {
      updateBannerText(banner, '🟡 Requesting Canvas API Token... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
    }

    const csrfToken = extractCsrfToken();

    if (!csrfToken) {
      isExecuting = false;
      if (banner) updateBannerText(banner, '🟡 Waiting Cookie/CSRF... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
      return;
    }

    // 🟢 Canvas LMS 公式 REST API エンドポイントへ POST
    const formData = new URLSearchParams();
    formData.append('token[purpose]', 'K.dot App Auto Sync');

    const response = await fetch('/api/v1/users/self/tokens', {
      method: 'POST',
      headers: {
        'X-CSRF-Token': csrfToken,
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: formData
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const data = await response.json();
    // 🟢 Canvas REST API レスポンスの data.token にアクセストークンが入ります
    const apiToken = data.token || data.visible_token || (data.access_token && data.access_token.visible_token);

    if (!apiToken) {
      throw new Error("Token payload empty");
    }

    extAPI.runtime.sendMessage({ action: "SYNC_TOKEN", token: apiToken }, (res) => {
      isExecuting = false;
      if (!banner) return;

      const lastErr = extAPI.runtime ? extAPI.runtime.lastError : null;
      if (lastErr) {
        updateBannerText(banner, '🔴 Comm Error: ' + lastErr.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
        return;
      }

      if (res && res.status === "success") {
        banner.dataset.synced = "true";
        updateBannerText(banner, '🟢 API Token Generated & Synced (' + res.tokenLength + ' chars)! Returning to App...');
        setTimeout(() => {
          window.location.href = "app3kportal://login-success";
        }, 300);
      } else {
        const reason = (res && res.reason) ? res.reason : "Sync Failed";
        updateBannerText(banner, '🔴 Token Sync Failed (' + reason + ') ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
      }
    });

  } catch (err) {
    isExecuting = false;
    const banner = document.getElementById('kdot-extension-banner');
    if (banner) {
      updateBannerText(banner, '🔴 Token Error: ' + err.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
    }
  }
}

setupBanner();
autoGenerateTokenAndSync();
setInterval(autoGenerateTokenAndSync, 2000);
