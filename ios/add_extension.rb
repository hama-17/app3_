require 'xcodeproj'
require 'fileutils'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

existing_target = project.targets.find { |t| t.name == 'RunnerExtension' }
if existing_target
  puts "RunnerExtension target already exists."
  exit 0
end

# 🟢 1. Entitlements (App Group) ファイルの自動作成
entitlements_dir = 'ios/RunnerExtension'
FileUtils.mkdir_p(entitlements_dir) unless Dir.exist?(entitlements_dir)

entitlements_content = <<~XML
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

entitlements_path = File.join(entitlements_dir, 'RunnerExtension.entitlements')
File.write(entitlements_path, entitlements_content)

# 2. 拡張機能ターゲットの定義
extension_target = project.new_target(:app_extension, 'RunnerExtension', :ios, '16.0')
extension_target.product_type = 'com.apple.product-type.app-extension'

extension_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.h.k.portal.extension'
  config.build_settings['INFOPLIST_FILE'] = 'RunnerExtension/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'RunnerExtension/RunnerExtension.entitlements' # 🟢 App Group 紐付け
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
end

# 3. ソースファイルおよびリソースの紐付け
group = project.main_group.find_subpath('RunnerExtension', true) || project.main_group.new_group('RunnerExtension', 'RunnerExtension')
group.set_source_tree('<group>')

swift_file = group.new_file('SafariExtensionHandler.swift')
manifest_file = group.new_file('manifest.json')
content_file = group.new_file('content.js')
background_file = group.new_file('background.js')
entitlements_file = group.new_file('RunnerExtension.entitlements')

extension_target.add_file_references([swift_file])

resources_phase = extension_target.resources_build_phase
resources_phase.add_file_reference(manifest_file)
resources_phase.add_file_reference(content_file)
resources_phase.add_file_reference(background_file)

# 4. SafariServices Framework のリンク設定
frameworks_phase = extension_target.frameworks_build_phase
sf_framework = project.frameworks_group.new_file('System/Library/Frameworks/SafariServices.framework')
sf_framework.source_tree = 'SDKROOT'
frameworks_phase.add_file_reference(sf_framework)

# 5. メインアプリ (Runner) への Embed (PlugIns フォルダへの同梱) 設定
main_target = project.targets.find { |t| t.name == 'Runner' }
main_target.add_dependency(extension_target)

embed_phase = main_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
unless embed_phase
  embed_phase = main_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end

# 🟢 CodeSignOnCopy 属性を付与
build_file = embed_phase.add_file_reference(extension_target.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy'] }

project.save
puts "Successfully added RunnerExtension target with CodeSignOnCopy and Entitlements to Xcode project."