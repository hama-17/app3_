browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.url && tab.url.includes('lms.keio.jp')) {
    browser.cookies.getAll({ url: "https://lms.keio.jp" }, (cookies) => {
      if (cookies && cookies.length > 0) {
        const cookieHeader = cookies.map(c => `${c.name}=${c.value}`).join('; ');
        browser.runtime.sendNativeMessage("application.id", { "cookie": cookieHeader }, (response) => {
          browser.tabs.sendMessage(tabId, { action: "REDIRECT_TO_APP" }).catch((err) => {
            console.log("Redirect message failed: ", err);
          });
        });
      }
    });
  }
});
