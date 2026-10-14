console.log("K.dot extension content script loaded on:", window.location.href);

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.action === "REDIRECT_TO_APP") {
    window.location.href = "app3kportal://login-success";
  }
});
