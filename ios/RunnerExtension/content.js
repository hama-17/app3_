const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

function setupBanner() {
  let banner = document.getElementById('kdot-extension-banner');
  if (!banner) {
    banner = document.createElement('div');
    banner.id = 'kdot-extension-banner';
    banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:8px;';
    banner.innerHTML = '🟡 K.dot 拡張機能テスト中...';
    document.body.appendChild(banner);
  }
  return banner;
}

function runTest() {
  const banner = setupBanner();
  extAPI.runtime.sendMessage({ action: "PING" }, (res) => {
    if (res && res.status === "success") {
      banner.style.background = "#2e7d32";
      banner.innerHTML = '🟢 App Group書き込み完了！ ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
    } else {
      banner.style.background = "#c62828";
      banner.innerHTML = '🔴 送信失敗';
    }
  });
}

setTimeout(runTest, 1000);
