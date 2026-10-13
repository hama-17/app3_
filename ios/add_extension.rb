require 'xcodeproj'
require 'fileutils'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 1. Entitlements (App Group) ファイルの自動作成
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

# 2. 拡張機能ターゲットの取得または新規作成
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
end

# 3. リソースとソースファイルの紐付け
group = project.main_group.find_subpath('RunnerExtension', true) || project.main_group.new_group('RunnerExtension', 'RunnerExtension')
group.set_source_tree('<group>')

swift_file = group.find_file_by_path('SafariExtensionHandler.swift') || group.new_file('SafariExtensionHandler.swift')
manifest_file = group.find_file_by_path('manifest.json') || group.new_file('manifest.json')
content_file = group.find_file_by_path('content.js') || group.new_file('content.js')
background_file = group.find_file_by_path('background.js') || group.new_file('background.js')

extension_target.add_file_references([swift_file])

resources_phase = extension_target.resources_build_phase
resources_phase.files.clear
resources_phase.add_file_reference(manifest_file)
resources_phase.add_file_reference(content_file)
resources_phase.add_file_reference(background_file)

# 4. Frameworks の設定
frameworks_phase = extension_target.frameworks_build_phase
sf_framework = project.frameworks_group.find_file_by_path('System/Library/Frameworks/SafariServices.framework') || project.frameworks_group.new_file('System/Library/Frameworks/SafariServices.framework')
sf_framework.source_tree = 'SDKROOT'
frameworks_phase.add_file_reference(sf_framework)

# 5. メインアプリ (Runner) への Embed フェーズの設定
main_target = project.targets.find { |t| t.name == 'Runner' }
main_target.add_dependency(extension_target) unless main_target.dependencies.any? { |d| d.target == extension_target }

embed_phase = main_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
unless embed_phase
  embed_phase = main_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end

build_file = embed_phase.files.find { |f| f.file_ref == extension_target.product_reference }
unless build_file
  build_file = embed_phase.add_file_reference(extension_target.product_reference, true)
end
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy'] }

project.save
puts "Successfully configured RunnerExtension target in project.pbxproj"