require 'xcodeproj'
require 'fileutils'
require 'rexml/document'
require 'base64'

begin
  puts "=== Starting Safari Extension Injection ==="

  project_path = 'ios/Runner.xcodeproj'
  project = Xcodeproj::Project.open(project_path)

  # 1. Runner側 Entitlements の物理生成
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

  # 2. Extension ディレクトリと構成ファイルの作成
  ext_dir = 'ios/RunnerExtension'
  FileUtils.mkdir_p(ext_dir)

  png_bytes = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
  ['icon-16.png', 'icon-32.png', 'icon-48.png', 'icon-128.png'].each do |icon_name|
    icon_path = File.join(ext_dir, icon_name)
    File.write(icon_path, png_bytes) unless File.exist?(icon_path)
  end

  info_plist_path = File.join(ext_dir, 'Info.plist')
  unless File.exist?(info_plist_path)
    File.write(info_plist_path, <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>$(DEVELOPMENT_LANGUAGE)</string>
        <key>CFBundleDisplayName</key>
        <string>RunnerExtension</string>
        <key>CFBundleExecutable</key>
        <string>$(EXECUTABLE_NAME)</string>
        <key>CFBundleIdentifier</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>$(PRODUCT_NAME)</string>
        <key>CFBundlePackageType</key>
        <string>XPC!</string>
        <key>CFBundleShortVersionString</key>
        <string>1.0</string>
        <key>CFBundleVersion</key>
        <string>1</string>
        <key>NSExtension</key>
        <dict>
           <key>NSExtensionPointIdentifier</key>
           <string>com.apple.Safari.web-extension</string>
           <key>NSExtensionPrincipalClass</key>
           <string>$(PRODUCT_MODULE_NAME).SafariExtensionHandler</string>
        </dict>
      </dict>
      </plist>
    XML
  end

  entitlements_path = File.join(ext_dir, 'RunnerExtension.entitlements')
  unless File.exist?(entitlements_path)
    File.write(entitlements_path, <<~XML)
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

  # 🟢 Swift ハンドラ
  swift_path = File.join(ext_dir, 'SafariExtensionHandler.swift')
  File.write(swift_path, <<~SWIFT)
    import SafariServices
    import Foundation

    class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
        func beginRequest(with context: NSExtensionContext) {
            guard let item = context.inputItems.first as? NSExtensionItem,
                  let userInfo = item.userInfo as? [String: Any],
                  let message = userInfo[SFExtensionMessageKey] as? [String: Any],
                  let cookie = message["cookie"] as? String else {
                let response = NSExtensionItem()
                response.userInfo = [ SFExtensionMessageKey: [ "status": "error", "reason": "payload_empty" ] ]
                context.completeRequest(returningItems: [response], completionHandler: nil)
                return
            }

            if let sharedDefaults = UserDefaults(suiteName: "group.com.h.k.portal") {
                sharedDefaults.set(cookie, forKey: "session_cookie")
                sharedDefaults.synchronize()

                let response = NSExtensionItem()
                response.userInfo = [ SFExtensionMessageKey: [ "status": "success" ] ]
                context.completeRequest(returningItems: [response], completionHandler: nil)
            } else {
                let response = NSExtensionItem()
                response.userInfo = [ SFExtensionMessageKey: [ "status": "error", "reason": "no_app_group" ] ]
                context.completeRequest(returningItems: [response], completionHandler: nil)
            }
        }
    }
  SWIFT

  manifest_path = File.join(ext_dir, 'manifest.json')
  File.write(manifest_path, <<~JSON)
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
        "cookies",
        "tabs",
        "https://lms.keio.jp/*",
        "https://*/*"
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

  # 🟢 堅牢な Cookie 取得＆ネイティブ送信 background.js
  bg_path = File.join(ext_dir, 'background.js')
  File.write(bg_path, <<~JS)
    browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
      if (message && message.action === "SYNC_COOKIE") {
        // 末尾スラッシュ付き URL で取得
        browser.cookies.getAll({ url: "https://lms.keio.jp/" }, (cookies) => {
          let cookieParts = [];
          if (cookies && cookies.length > 0) {
            cookieParts.push(cookies.map(c => `${c.name}=${c.value}`).join('; '));
          }
          if (message.fallbackCookie && message.fallbackCookie.length > 0) {
            cookieParts.push(message.fallbackCookie);
          }

          const fullCookie = cookieParts.join('; ');

          if (!fullCookie || fullCookie.trim().length === 0) {
            sendResponse({ status: "error", reason: "Cookie未検出(ログイン完了待ち)" });
            return;
          }

          browser.runtime.sendNativeMessage("application.id", { "cookie": fullCookie }, (response) => {
            if (browser.runtime.lastError) {
              sendResponse({ status: "error", reason: "Native通信失敗: " + browser.runtime.lastError.message });
            } else if (response && response.status === "success") {
              sendResponse({ status: "success", cookieLength: fullCookie.length });
            } else {
              const errDetail = (response && response.reason) ? response.reason : "Native書き込み失敗";
              sendResponse({ status: "error", reason: errDetail });
            }
          });
        });
        return true; // 非同期応答を有効化
      }
    });
  JS

  # 🟢 フォールバック送信 ＆ 詳細エラーバナー content.js
  content_path = File.join(ext_dir, 'content.js')
  File.write(content_path, <<~JS)
    function setupBanner() {
      if (!document.getElementById('kdot-extension-banner')) {
        const banner = document.createElement('div');
        banner.id = 'kdot-extension-banner';
        banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:6px;box-shadow:0 2px 5px rgba(0,0,0,0.3);';
        banner.innerHTML = 'K.dot 拡張機能初期化中...';
        document.body.appendChild(banner);
      }
    }

    function checkAndSyncCookie() {
      setupBanner();
      const banner = document.getElementById('kdot-extension-banner');

      if (window.location.href.includes('/login') || window.location.href.includes('/saml')) {
        if (banner) {
          banner.innerHTML = '🟡 K.dot 拡張機能動作中 (パスキー認証を行ってください) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
        }
        return;
      }

      const docCookie = document.cookie || "";

      browser.runtime.sendMessage({ action: "SYNC_COOKIE", fallbackCookie: docCookie }).then((response) => {
        if (!banner) return;
        if (response && response.status === "success") {
          banner.dataset.synced = "true";
          banner.innerHTML = '🟢 App Groupへ送信完了！ (' + response.cookieLength + '文字) ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;font-weight:bold;text-decoration:underline;">[タップしてアプリへ戻る]</a>';
        } else {
          const reason = (response && response.reason) ? response.reason : "処理中...";
          banner.innerHTML = '🟡 同期待機中 (' + reason + ') ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
        }
      }).catch((e) => {
        if (banner) {
          banner.innerHTML = '🔴 通信エラー: ' + e.message + ' ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
        }
      });
    }

    setupBanner();
    setInterval(checkAndSyncCookie, 2000);
  JS

  # 3. Extension Target の取得・生成
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
  abort 'ERROR: Runner target not found' unless main_target

  main_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  end

  unless main_target.dependencies.any? { |d| d.target == extension_target }
    main_target.add_dependency(extension_target)
  end

  embed_phase = main_target.copy_files_build_phases.find do |phase|
    phase.name == 'Embed App Extensions'
  end

  unless embed_phase
    embed_phase = main_target.new_copy_files_build_phase('Embed App Extensions')
  end

  embed_phase.symbol_dst_subfolder_spec = :plug_ins
  embed_phase.dst_path = ''

  product_ref = extension_target.product_reference
  abort 'ERROR: Extension product reference missing' unless product_ref

  matching_files = embed_phase.files.select do |file|
    file.file_ref == product_ref
  end

  build_file = matching_files.first
  if build_file.nil?
    build_file = embed_phase.add_file_reference(product_ref, true)
  end

  matching_files.drop(1).each do |duplicate|
    embed_phase.remove_build_file(duplicate)
  end

  build_file.settings = {
    'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy']
  }

  resources_phase_index = main_target.build_phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase) }
  if resources_phase_index
    main_target.build_phases.delete(embed_phase)
    main_target.build_phases.insert(resources_phase_index + 1, embed_phase)
  end

  project.save
  puts "Successfully configured Runner and RunnerExtension targets with all resources."

  scheme_paths = Dir.glob('ios/**/*.xcscheme')
  runner_scheme = scheme_paths.find { |p| p.include?('Runner.xcscheme') }

  if runner_scheme && File.exist?(runner_scheme)
    scheme_content = File.read(runner_scheme)
    unless scheme_content.include?('BlueprintName = "RunnerExtension"')
      target_uuid = extension_target.uuid
      entry_xml = <<~XML
            <BuildActionEntry
               buildForTesting = "YES"
               buildForRunning = "YES"
               buildForProfiling = "YES"
               buildForArchiving = "YES"
               buildForAnalyzing = "YES">
               <BuildableReference
                  BuildableIdentifier = "primary"
                  BlueprintIdentifier = "#{target_uuid}"
                  BuildableName = "RunnerExtension.appex"
                  BlueprintName = "RunnerExtension"
                  ReferencedContainer = "container:Runner.xcodeproj">
               </BuildableReference>
            </BuildActionEntry>
      XML

      updated_content = scheme_content.sub('</BuildActionEntries>', "#{entry_xml}\n      </BuildActionEntries>")
      File.write(runner_scheme, updated_content)
      puts "Successfully injected RunnerExtension into #{runner_scheme}"
    end
  end

  puts "=== Safari Extension Injection Completed Successfully ==="

rescue => e
  puts "❌ ERROR during script execution: #{e.message}"
  puts e.backtrace
  exit 1
end