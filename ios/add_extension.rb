require 'xcodeproj'
require 'fileutils'
require 'rexml/document'
require 'base64'

begin
  puts "=== Starting Safari Extension Injection (Option A: /api/v1 Endpoint Fix) ==="

  project_path = 'ios/Runner.xcodeproj'
  project = Xcodeproj::Project.open(project_path)

  # 1. Runner 側の Entitlements の物理生成
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

            var tokenStr: String? = nil
            if let message = userInfo[SFExtensionMessageKey] as? [String: Any] {
                tokenStr = (message["token"] as? String) ?? (message["cookie"] as? String)
            } else if let token = (userInfo["token"] as? String) ?? (userInfo["cookie"] as? String) {
                tokenStr = token
            }

            guard let token = tokenStr, !token.isEmpty else {
                sendResponse(context: context, status: "error", reason: "payload_empty")
                return
            }

            if let sharedDefaults = UserDefaults(suiteName: "group.com.h.k.portal") {
                sharedDefaults.set(token, forKey: "session_cookie")
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
      "description": "API Token auto sync extension for K.dot portal",
      "icons": {
        "16": "icon-16.png",
        "32": "icon-32.png",
        "48": "icon-48.png",
        "128": "icon-128.png"
      },
      "permissions": [
        "nativeMessaging",
        "tabs",
        "https://lms.keio.jp/*"
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

  # 🟢 background.js (正確な NATIVE_APP_ID に修正済み)
  File.write(File.join(ext_dir, 'background.js'), <<~JS)
    const extAPI = (typeof browser !== 'undefined') ? browser : chrome;
    const NATIVE_APP_ID = "com.h.k.portal.extension";

    extAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
      if (message && message.action === "SYNC_TOKEN") {
        const token = message.token;
        if (!token) {
          sendResponse({ status: "error", reason: "Token Empty" });
          return true;
        }

        extAPI.runtime.sendNativeMessage(NATIVE_APP_ID, { "token": token }, (response) => {
          const err = extAPI.runtime ? extAPI.runtime.lastError : null;
          if (err) {
            sendResponse({ status: "error", reason: "Native Err: " + err.message });
          } else if (response && response.status === "success") {
            sendResponse({ status: "success", tokenLength: token.length });
          } else {
            const errDetail = (response && response.reason) ? response.reason : "Native Sync Fail";
            sendResponse({ status: "error", reason: errDetail });
          }
        });

        return true;
      }
    });
  JS

  # 🟢 content.js (無限生成防止 & 安全な同期制御に修正済み)
  File.write(File.join(ext_dir, 'content.js'), <<~JS)
    const extAPI = (typeof browser !== 'undefined') ? browser : chrome;
    let isExecuting = false;
    let lastBannerText = "";

    function updateBannerText(banner, text) {
      if (lastBannerText !== text) {
        lastBannerText = text;
        banner.innerHTML = text;
      }
    }

    function setupBanner() {
      let banner = document.getElementById('kdot-extension-banner');
      if (!banner) {
        banner = document.createElement('div');
        banner.id = 'kdot-extension-banner';
        banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:6px;box-shadow:0 2px 5px rgba(0,0,0,0.3);';
        updateBannerText(banner, '🟡 K.dot Extension Working... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
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

    function extractCsrfToken() {
      const metaToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
                     || document.querySelector('meta[name="authenticity-token"]')?.getAttribute('content');
      if (metaToken) return metaToken;

      const cookies = document.cookie.split(';');
      for (let i = 0; i < cookies.length; i++) {
        const pair = cookies[i].trim().split('=');
        if (pair[0] === '_csrf_token' || pair[0] === 'csrf_token') {
          return decodeURIComponent(pair.slice(1).join('='));
        }
      }

      return null;
    }

    async function autoGenerateTokenAndSync() {
      if (isExecuting) return;

      const banner = setupBanner();

      if (sessionStorage.getItem('kdot_synced') === 'true' || (banner && banner.dataset.synced === "true")) {
        return;
      }

      if (window.location.href.includes('/login') || window.location.href.includes('/saml')) {
        if (banner) {
          updateBannerText(banner, '🟡 K.dot Extension (Please complete Passkey login) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
        }
        return;
      }

      const csrfToken = extractCsrfToken();
      if (!csrfToken) {
        if (banner) updateBannerText(banner, '🟡 Waiting Cookie/CSRF... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
        return;
      }

      isExecuting = true;
      if (banner) {
        updateBannerText(banner, '🟡 Requesting Canvas API Token... ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
      }

      try {
        const formData = new URLSearchParams();
        formData.append('token[purpose]', 'K.dot App Auto Sync');

        const response = await fetch('/api/v1/users/self/tokens', {
          method: 'POST',
          headers: {
            'X-CSRF-Token': csrfToken,
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded'
          },
          body: formData
        });

        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }

        const data = await response.json();
        const apiToken = data.token || data.visible_token || (data.access_token && data.access_token.visible_token);

        if (!apiToken) {
          throw new Error("Token payload empty");
        }

        extAPI.runtime.sendMessage({ action: "SYNC_TOKEN", token: apiToken }, (res) => {
          isExecuting = false;
          if (!banner) return;

          const lastErr = extAPI.runtime ? extAPI.runtime.lastError : null;
          if (lastErr) {
            updateBannerText(banner, '🔴 Comm Error: ' + lastErr.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
            return;
          }

          if (res && res.status === "success") {
            banner.dataset.synced = "true";
            sessionStorage.setItem('kdot_synced', 'true');
            updateBannerText(banner, '🟢 API Token Synced (' + res.tokenLength + ' chars)! Returning to App...');

            setTimeout(() => {
              window.location.href = "app3kportal://login-success";
            }, 500);
          } else {
            const reason = (res && res.reason) ? res.reason : "Sync Failed";
            updateBannerText(banner, '🔴 Token Sync Failed (' + reason + ') ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
          }
        });

      } catch (err) {
        isExecuting = false;
        if (banner) {
          updateBannerText(banner, '🔴 Token Error: ' + err.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[Back to App]</a>');
        }
      }
    }

    setupBanner();
    autoGenerateTokenAndSync();

    const timerId = setInterval(() => {
      if (sessionStorage.getItem('kdot_synced') === 'true') {
        clearInterval(timerId);
      } else {
        autoGenerateTokenAndSync();
      }
    }, 3000);
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
  puts "Successfully configured Runner and RunnerExtension with official Canvas REST API endpoint (/api/v1/users/self/tokens)."

rescue => e
  puts "❌ ERROR during script execution: #{e.message}"
  exit 1
end