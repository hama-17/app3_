// ダッシュボード等に到達したらクッキーをネイティブへ送信
if (window.location.href.includes("/dashboard") || window.location.href.includes("/home")) {
  const cookieData = document.cookie;
  browser.runtime.sendNativeMessage("application.id", { "cookie": cookieData });
}