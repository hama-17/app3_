if (!document.getElementById('kdot-extension-banner')) {
  const banner = document.createElement('div');
  banner.id = 'kdot-extension-banner';
  banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:13px;padding:6px;box-shadow:0 2px 5px rgba(0,0,0,0.3);';
  banner.innerHTML = 'K.dot 拡張機能動作中 ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;font-weight:bold;text-decoration:underline;">[タップしてアプリへ戻る]</a>';
  document.body.appendChild(banner);
}

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "REDIRECT_TO_APP") {
    window.location.href = "app3kportal://login-success";
  }
});
