require 'xcodeproj'
require 'fileutils'
require 'rexml/document'
require 'base64'

begin
  puts "=== Starting Safari Extension Injection ==="

  project_path = 'ios/Runner.xcodeproj'
  project = Xcodeproj::Project.open(project_path)

  # 1. Runner側 Entitlements
  runner_entitlements_path = File.join('ios/Runner', 'Runner.entitlements')
  unless File.exist?(runner_entitlements_path)
    File.write(runner_entitlements_path, <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>com.apple.security.application-groups</key>
        <array>
           <string>group.com.h.k.portal</string>
        </array>
      </dict>
      </plist>
    XML
  end

  # 2. Extension ディレクトリ構成
  ext_dir = 'ios/RunnerExtension'
  FileUtils.mkdir_p(ext_dir)

  png_bytes = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
  ['icon-16.png', 'icon-32.png', 'icon-48.png', 'icon-128.png'].each do |icon_name|
    icon_path = File.join(ext_dir, icon_name)
    File.write(icon_path, png_bytes) unless File.exist?(icon_path)
  end

  File.write(File.join(ext_dir, 'Info.plist'), <<~XML) unless File.exist?(File.join(ext_dir, 'Info.plist'))
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key><string>$(DEVELOPMENT_LANGUAGE)</string>
      <key>CFBundleDisplayName</key><string>RunnerExtension</string>
      <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
      <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
      <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
      <key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
      <key>CFBundlePackageType</key><string>XPC!</string>
      <key>CFBundleShortVersionString</key><string>1.0</string>
      <key>CFBundleVersion</key><string>1</string>
      <key>NSExtension</key>
      <dict>
         <key>NSExtensionPointIdentifier</key><string>com.apple.Safari.web-extension</string>
         <key>NSExtensionPrincipalClass</key><string>$(PRODUCT_MODULE_NAME).SafariExtensionHandler</string>
      </dict>
    </dict>
    </plist>
  XML

  File.write(File.join(ext_dir, 'RunnerExtension.entitlements'), <<~XML) unless File.exist?(File.join(ext_dir, 'RunnerExtension.entitlements'))
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>com.apple.security.application-groups</key>
      <array>
         <string>group.com.h.k.portal</string>
      </array>
    </dict>
    </plist>
  XML

  # 🟢 Swift ハンドラ
  File.write(File.join(ext_dir, 'SafariExtensionHandler.swift'), <<~SWIFT)
    import SafariServices
    import Foundation

    class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
        func beginRequest(with context: NSExtensionContext) {
            guard let item = context.inputItems.first as? NSExtensionItem,
                  let userInfo = item.userInfo as? [String: Any] else {
                sendResponse(context: context, status: "error", reason: "no_user_info")
                return
            }

            var cookieStr: String? = nil
            if let message = userInfo[SFExtensionMessageKey] as? [String: Any] {
                cookieStr = message["cookie"] as? String
            } else if let cookie = userInfo["cookie"] as? String {
                cookieStr = cookie
            }

            guard let cookie = cookieStr, !cookie.isEmpty else {
                sendResponse(context: context, status: "error", reason: "payload_empty")
                return
            }

            if let sharedDefaults = UserDefaults(suiteName: "group.com.h.k.portal") {
                sharedDefaults.set(cookie, forKey: "session_cookie")
                sharedDefaults.synchronize()
                sendResponse(context: context, status: "success", reason: nil)
            } else {
                sendResponse(context: context, status: "error", reason: "no_app_group")
            }
        }

        private func sendResponse(context: NSExtensionContext, status: String, reason: String?) {
            let response = NSExtensionItem()
            var resDict: [String: Any] = ["status": status]
            if let reason = reason {
                resDict["reason"] = reason
            }
            response.userInfo = [SFExtensionMessageKey: resDict]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }
  SWIFT

  # 🟢 manifest.json
  File.write(File.join(ext_dir, 'manifest.json'), <<~JSON)
    {
      "manifest_version": 2,
      "name": "K.dot Extension",
      "version": "1.0",
      "description": "Cookie sync extension for K.dot portal",
      "icons": {
        "16": "icon-16.png",
        "32": "icon-32.png",
        "48": "icon-48.png",
        "128": "icon-128.png"
      },
      "permissions": [
        "nativeMessaging",
        "cookies",
        "tabs",
        "https://lms.keio.jp/*",
        "https://*.keio.jp/*"
      ],
      "content_scripts": [
        {
          "matches": ["https://lms.keio.jp/*"],
          "js": ["content.js"],
          "run_at": "document_end"
        }
      ],
      "background": {
        "scripts": ["background.js"],
        "persistent": false
      }
    }
  JSON

  # 🟢 タブURL直接参照 ＆ _canvas_session 厳格確認 background.js
  File.write(File.join(ext_dir, 'background.js'), <<~JS)
    const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

    extAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
      if (message && message.action === "SYNC_COOKIE") {
        let responded = false;

        const safeResponse = (data) => {
          if (!responded) {
            responded = true;
            clearTimeout(timer);
            try { sendResponse(data); } catch(e) {}
          }
        };

        const timer = setTimeout(() => {
          safeResponse({ status: "error", reason: "BG Timeout (3s)" });
        }, 3000);

        try {
          const currentTabUrl = (sender && sender.tab && sender.tab.url) ? sender.tab.url : "https://lms.keio.jp/";
          let cookieMap = new Map();

          // 1. アクティブタブのURLから直接 HttpOnly クッキーを取得
          extAPI.cookies.getAll({ url: currentTabUrl }, (cookiesTab) => {
            if (cookiesTab) {
              cookiesTab.forEach(c => {
                if (c && c.name && c.value) cookieMap.set(c.name, c.value);
              });
            }

            // 2. LMSルートURLからも相乗取得
            extAPI.cookies.getAll({ url: "https://lms.keio.jp/" }, (cookiesRoot) => {
              if (cookiesRoot) {
                cookiesRoot.forEach(c => {
                  if (c && c.name && c.value) cookieMap.set(c.name, c.value);
                });
              }

              // 3. fallback (document.cookie)
              if (message.fallbackCookie) {
                message.fallbackCookie.split(';').forEach(pair => {
                  const parts = pair.split('=');
                  if (parts.length >= 2) {
                    const k = parts[0].trim();
                    const v = parts.slice(1).join('=').trim();
                    if (k && !cookieMap.has(k)) cookieMap.set(k, v);
                  }
                });
              }

              let cookiePairs = [];
              let detectedNames = [];
              let hasCanvasSession = false;

              cookieMap.forEach((v, k) => {
                cookiePairs.push(`${k}=${v}`);
                detectedNames.push(k);
                if (k.includes('canvas_session')) {
                  hasCanvasSession = true;
                }
              });

              const fullCookie = cookiePairs.join('; ');
              const namesSummary = detectedNames.length > 0 ? detectedNames.join(',') : 'なし';

              // 🟢 _canvas_session が見つからない、または 200 文字未満の場合は一切送信しない（古いデータの誤書き込み防止）
              if (!hasCanvasSession || fullCookie.length < 200) {
                safeResponse({ status: "error", reason: `ログイン完了待ち (検出:[${namesSummary}] / 長さ:${fullCookie.length}文字)` });
                return;
              }

              sendToNative(fullCookie, safeResponse);
            });
          });
        } catch (e) {
          safeResponse({ status: "error", reason: "BG Exception: " + e.message });
        }

        return true;
      }
    });

    function sendToNative(cookieString, safeResponse) {
      try {
        const extAPI = (typeof browser !== 'undefined') ? browser : chrome;
        extAPI.runtime.sendNativeMessage("application.id", { "cookie": cookieString }, (response) => {
          const err = extAPI.runtime ? extAPI.runtime.lastError : null;
          if (err) {
            safeResponse({ status: "error", reason: "Native Err: " + err.message });
          } else if (response && response.status === "success") {
            safeResponse({ status: "success", cookieLength: cookieString.length });
          } else {
            const errDetail = (response && response.reason) ? response.reason : "Native Sync Fail";
            safeResponse({ status: "error", reason: errDetail });
          }
        });
      } catch (e) {
        safeResponse({ status: "error", reason: "Native Exception: " + e.message });
      }
    }
  JS

  # 🟢 content.js
  File.write(File.join(ext_dir, 'content.js'), <<~JS)
    const extAPI = (typeof browser !== 'undefined') ? browser : chrome;
    let isSyncing = false;

    function setupBanner() {
      let banner = document.getElementById('kdot-extension-banner');
      if (!banner) {
        banner = document.createElement('div');
        banner.id = 'kdot-extension-banner';
        banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:6px;box-shadow:0 2px 5px rgba(0,0,0,0.3);';
        banner.innerHTML = '🟡 K.dot 拡張機能動作中... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
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

    function checkAndSyncCookie() {
      if (isSyncing) return;

      try {
        const banner = setupBanner();

        if (banner && banner.dataset.synced === "true") {
          return;
        }

        if (window.location.href.includes('/login') || window.location.href.includes('/saml')) {
          if (banner) {
            banner.innerHTML = '🟡 K.dot 拡張機能動作中 (パスキー認証を完了させてください) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
          }
          return;
        }

        isSyncing = true;
        const docCookie = document.cookie || "";

        if (banner && !banner.dataset.synced) {
          banner.innerHTML = '🟡 認証セッション確認中... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
        }

        const lockTimer = setTimeout(() => {
          if (isSyncing) isSyncing = false;
        }, 3000);

        extAPI.runtime.sendMessage({ action: "SYNC_COOKIE", fallbackCookie: docCookie }, (response) => {
          clearTimeout(lockTimer);
          isSyncing = false;
          if (!banner) return;

          const lastErr = extAPI.runtime ? extAPI.runtime.lastError : null;
          if (lastErr) {
            banner.innerHTML = '🔴 通信エラー: ' + lastErr.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
            return;
          }

          if (response && response.status === "success") {
            banner.dataset.synced = "true";
            banner.innerHTML = '🟢 本物セッション同期成功 (' + response.cookieLength + '文字)! アプリへ自動復帰中...';
            setTimeout(() => {
              window.location.href = "app3kportal://login-success";
            }, 300);
          } else {
            const reason = (response && response.reason) ? response.reason : "待機中";
            banner.innerHTML = '🟡 同期待機中 (' + reason + ') ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
          }
        });
      } catch (err) {
        isSyncing = false;
        const banner = document.getElementById('kdot-extension-banner');
        if (banner) {
          banner.innerHTML = '🔴 JS Exception: ' + err.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
        }
      }
    }

    setupBanner();
    checkAndSyncCookie();
    setInterval(checkAndSyncCookie, 1500);
  JS

  # 3. Target 構成
  extension_target = project.targets.find { |t| t.name == 'RunnerExtension' }
  unless extension_target
    extension_target = project.new_target(:app_extension, 'RunnerExtension', :ios, '16.0')
    extension_target.product_type = 'com.apple.product-type.app-extension'
  end

  extension_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_NAME'] = 'RunnerExtension'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.h.k.portal.extension'
    config.build_settings['INFOPLIST_FILE'] = 'RunnerExtension/Info.plist'
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'RunnerExtension/RunnerExtension.entitlements'
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    config.build_settings['SKIP_INSTALL'] = 'YES'
  end

  group = project.main_group.find_subpath('RunnerExtension', true) || project.main_group.new_group('RunnerExtension', 'RunnerExtension')
  group.path = 'RunnerExtension'
  group.source_tree = '<group>'

  swift_file = group.files.find { |f| f.path == 'SafariExtensionHandler.swift' } || group.new_file('SafariExtensionHandler.swift')
  manifest_file = group.files.find { |f| f.path == 'manifest.json' } || group.new_file('manifest.json')
  content_file = group.files.find { |f| f.path == 'content.js' } || group.new_file('content.js')
  background_file = group.files.find { |f| f.path == 'background.js' } || group.new_file('background.js')

  icon_files = ['icon-16.png', 'icon-32.png', 'icon-48.png', 'icon-128.png'].map do |name|
    group.files.find { |f| f.path == name } || group.new_file(name)
  end

  extension_target.add_file_references([swift_file])

  resources_phase = extension_target.resources_build_phase
  resources_phase.files.clear
  resources_phase.add_file_reference(manifest_file)
  resources_phase.add_file_reference(content_file)
  resources_phase.add_file_reference(background_file)
  icon_files.each { |icon_f| resources_phase.add_file_reference(icon_f) }

  frameworks_phase = extension_target.frameworks_build_phase
  sf_framework = project.frameworks_group.files.find { |f| f.path == 'System/Library/Frameworks/SafariServices.framework' } ||
                 project.frameworks_group.new_file('System/Library/Frameworks/SafariServices.framework')
  sf_framework.source_tree = 'SDKROOT'
  unless frameworks_phase.files.any? { |f| f.file_ref == sf_framework }
    frameworks_phase.add_file_reference(sf_framework)
  end

  main_target = project.targets.find { |t| t.name == 'Runner' }
  main_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  end

  unless main_target.dependencies.any? { |d| d.target == extension_target }
    main_target.add_dependency(extension_target)
  end

  embed_phase = main_target.copy_files_build_phases.find { |phase| phase.name == 'Embed App Extensions' } ||
                main_target.new_copy_files_build_phase('Embed App Extensions')

  embed_phase.symbol_dst_subfolder_spec = :plug_ins
  embed_phase.dst_path = ''

  product_ref = extension_target.product_reference
  matching_files = embed_phase.files.select { |file| file.file_ref == product_ref }
  build_file = matching_files.first || embed_phase.add_file_reference(product_ref, true)

  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy'] }

  project.save
  puts "Successfully configured Runner and RunnerExtension targets with all resources."

rescue => e
  puts "❌ ERROR during script execution: #{e.message}"
  exit 1
end