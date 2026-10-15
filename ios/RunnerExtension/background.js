const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

extAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
  extAPI.runtime.sendNativeMessage("application.id", { test: "ping" }, (response) => {
    sendResponse({ status: "success" });
  });
  return true;
});
