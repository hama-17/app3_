// background.js からのアプリ復帰メッセージを受信してリダイレクト
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "REDIRECT_TO_APP") {
    // 画面上でリダイレクトを実行（これで iOS のブロックを回避）
    window.location.href = "app3kportal://login-success";
  }
});