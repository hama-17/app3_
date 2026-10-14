require 'xcodeproj'
require 'fileutils'
require 'rexml/document'

begin
  puts "=== Starting Safari Extension Injection ==="

  project_path = 'ios/Runner.xcodeproj'
  project = Xcodeproj::Project.open(project_path)

  # 1. ディレクトリと構成ファイルの作成
  ext_dir = 'ios/RunnerExtension'
  FileUtils.mkdir_p(ext_dir)

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

  swift_path = File.join(ext_dir, 'SafariExtensionHandler.swift')
  unless File.exist?(swift_path)
    File.write(swift_path, <<~SWIFT)
      import SafariServices

      class SafariExtensionHandler: NSObject, NSExtensionRequestHandling {
          func beginRequest(with context: NSExtensionContext) {}
      }
    SWIFT
  end

  manifest_path = File.join(ext_dir, 'manifest.json')
  unless File.exist?(manifest_path)
    File.write(manifest_path, <<~JSON)
      {
        "manifest_version": 3,
        "name": "K.dot Extension",
        "version": "1.0",
        "description": "Cookie Sync Extension for K.dot",
        "permissions": ["cookies"],
        "host_permissions": ["https://*/*"],
        "background": { "scripts": ["background.js"] }
      }
    JSON
  end

  bg_path = File.join(ext_dir, 'background.js')
  unless File.exist?(bg_path)
    File.write(bg_path, <<~JS)
      browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
        if (changeInfo.status === 'complete' && tab.url && (tab.url.includes('/dashboard') || tab.url.includes('/home') || tab.url.includes('/portal'))) {
          browser.cookies.getAll({ url: tab.url }, (cookies) => {
            if (cookies && cookies.length > 0) {
              const cookieHeader = cookies.map(c => `${c.name}=${c.value}`).join('; ');
              browser.runtime.sendNativeMessage("application.id", { "cookie": cookieHeader });
              setTimeout(() => {
                browser.tabs.update(tabId, { url: "app3kportal://login-success" });
              }, 300);
            }
          });
        }
      });
    JS
  end

  content_path = File.join(ext_dir, 'content.js')
  unless File.exist?(content_path)
    File.write(content_path, "// Content script\n")
  end

  # 2. Extension Target の取得・生成
  extension_target = project.targets.find { |t| t.name == 'RunnerExtension' }
  unless extension_target
    extension_target = project.new_target(:app_extension, 'RunnerExtension', :ios, '16.0')
    extension_target.product_type = 'com.apple.product-type.app-extension'
  end

  extension_target.build_configurations.each do |config|
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

  # 3. リソースとソースファイルの紐付け
  group = project.main_group.find_subpath('RunnerExtension', true) || project.main_group.new_group('RunnerExtension', 'RunnerExtension')
  group.set_source_tree('<group>')

  swift_file = group.files.find { |f| f.path == 'SafariExtensionHandler.swift' } || group.new_file('SafariExtensionHandler.swift')
  manifest_file = group.files.find { |f| f.path == 'manifest.json' } || group.new_file('manifest.json')
  content_file = group.files.find { |f| f.path == 'content.js' } || group.new_file('content.js')
  background_file = group.files.find { |f| f.path == 'background.js' } || group.new_file('background.js')

  extension_target.add_file_references([swift_file])

  resources_phase = extension_target.resources_build_phase
  resources_phase.files.clear
  resources_phase.add_file_reference(manifest_file)
  resources_phase.add_file_reference(content_file)
  resources_phase.add_file_reference(background_file)

  # 4. Frameworks 設定
  frameworks_phase = extension_target.frameworks_build_phase
  sf_framework = project.frameworks_group.files.find { |f| f.path == 'System/Library/Frameworks/SafariServices.framework' } ||
                 project.frameworks_group.new_file('System/Library/Frameworks/SafariServices.framework')
  sf_framework.source_tree = 'SDKROOT'
  unless frameworks_phase.files.any? { |f| f.file_ref == sf_framework }
    frameworks_phase.add_file_reference(sf_framework)
  end

  # 5. Target Dependency と Embed App Extensions の安全な接続
  main_target = project.targets.find { |t| t.name == 'Runner' }
  abort 'ERROR: Runner target not found' unless main_target

  unless main_target.dependencies.any? { |d| d.target == extension_target }
    main_target.add_dependency(extension_target)
  end

  embed_phase = main_target.copy_files_build_phases.find do |phase|
    phase.name == 'Embed App Extensions'
  end

  unless embed_phase
    embed_phase = main_target.new_copy_files_build_phase('Embed App Extensions')
  end

  # Xcodeprojにおける PlugIns (13) の指定
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

  project.save
  puts "Successfully configured RunnerExtension target and embed phase."

  # 🟢 6. 【核心】Runner.xcscheme へ RunnerExtension のビルド命令を物理挿入
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
  else
    puts "⚠️ Warning: Runner.xcscheme not found."
  end

  puts "=== Safari Extension Injection Completed Successfully ==="

rescue => e
  puts "❌ ERROR during script execution: #{e.message}"
  puts e.backtrace
  exit 1
end