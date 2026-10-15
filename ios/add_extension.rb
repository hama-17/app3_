require 'xcodeproj'
require 'fileutils'
require 'base64'

begin
  puts "=== Starting Minimal Safari Extension Injection ==="

  project_path = 'ios/Runner.xcodeproj'
  project = Xcodeproj::Project.open(project_path)

  # 1. Runner側 Entitlements
  runner_entitlements_path = File.join('ios/Runner', 'Runner.entitlements')
  File.write(runner_entitlements_path, <<~XML) unless File.exist?(runner_entitlements_path)
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

  # 🟢 超単純・堅牢な Swift ハンドラ
  File.write(File.join(ext_dir, 'SafariExtensionHandler.swift'), <<~SWIFT)
    import SafariServices
    import Foundation

    class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
        func beginRequest(with context: NSExtensionContext) {
            let sharedDefaults = UserDefaults(suiteName: "group.com.h.k.portal")

            // 受信データを書き込み
            let dummyData = "TEST_SESSION_COOKIE_SUCCESS_12345"
            sharedDefaults?.set(dummyData, forKey: "session_cookie")
            sharedDefaults?.synchronize()

            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: ["status": "ok"]]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }
  SWIFT

  File.write(File.join(ext_dir, 'manifest.json'), <<~JSON)
    {
      "manifest_version": 2,
      "name": "K.dot Extension",
      "version": "1.0",
      "description": "Cookie sync extension for K.dot portal",
      "icons": { "16": "icon-16.png", "32": "icon-32.png", "48": "icon-48.png", "128": "icon-128.png" },
      "permissions": ["cookies", "tabs", "https://lms.keio.jp/*"],
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

  # 🟢 超シンプル background.js
  File.write(File.join(ext_dir, 'background.js'), <<~JS)
    const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

    extAPI.runtime.onMessage.addListener((message, sender, sendResponse) => {
      extAPI.runtime.sendNativeMessage("application.id", { test: "ping" }, (response) => {
        sendResponse({ status: "success" });
      });
      return true;
    });
  JS

  # 🟢 超シンプル content.js
  File.write(File.join(ext_dir, 'content.js'), <<~JS)
    const extAPI = (typeof browser !== 'undefined') ? browser : chrome;

    function setupBanner() {
      let banner = document.getElementById('kdot-extension-banner');
      if (!banner) {
        banner = document.createElement('div');
        banner.id = 'kdot-extension-banner';
        banner.style.cssText = 'position:fixed;top:0;left:0;width:100%;background:#0066cc;color:white;text-align:center;z-index:999999;font-size:12px;padding:8px;';
        banner.innerHTML = '🟡 K.dot 拡張機能テスト中...';
        document.body.appendChild(banner);
      }
      return banner;
    }

    function runTest() {
      const banner = setupBanner();
      extAPI.runtime.sendMessage({ action: "PING" }, (res) => {
        if (res && res.status === "success") {
          banner.style.background = "#2e7d32";
          banner.innerHTML = '🟢 App Group書き込み完了！ ｜ <a href="app3kportal://login-success" style="color:#ffeb3b;">[アプリへ戻る]</a>';
        } else {
          banner.style.background = "#c62828";
          banner.innerHTML = '🔴 送信失敗';
        }
      });
    }

    setTimeout(runTest, 1000);
  JS

  # Xcode プロジェクトターゲット構築
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
  puts "=== Minimal Safari Extension Setup Completed ==="

rescue => e
  puts "❌ ERROR: #{e.message}"
  exit 1
end