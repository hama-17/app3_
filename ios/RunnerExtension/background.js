browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.url && tab.url.includes('lms.keio.jp')) {
    if (tab.url.includes('/login/saml') || tab.url.includes('/saml/consume')) {
      return;
    }

    browser.cookies.getAll({ url: "https://lms.keio.jp" }, (cookies) => {
      if (cookies && cookies.length > 0) {
        const cookieHeader = cookies.map(c => `${c.name}=${c.value}`).join('; ');

        browser.runtime.sendNativeMessage("application.id", { "cookie": cookieHeader }, (response) => {
          console.log("Native response:", response);
        });

        setTimeout(() => {
          browser.tabs.sendMessage(tabId, { action: "REDIRECT_TO_APP" }).catch((err) => {
            console.log("Redirect message failed: ", err);
          });
        }, 300);
      }
    });
  }
});
