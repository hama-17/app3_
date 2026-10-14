// 🟢 読み込み成功時に画面最上部に青いバーを表示（目視デバッグ用）
const banner = document.createElement('div');
banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:blue;color:white;text-align:center;z-index:999999;font-size:14px;padding:4px;';
banner.innerText = 'K.dot 拡張機能が正常動作中';
document.body.appendChild(banner);

// background.js からのアプリ復帰命令を受信
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "REDIRECT_TO_APP") {
    // ディープリンクを発火
    window.location.href = "app3kportal://login-success";
  }
});