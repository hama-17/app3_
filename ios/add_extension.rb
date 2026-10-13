require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

existing_target = project.targets.find { |t| t.name == 'RunnerExtension' }
if existing_target
  puts "RunnerExtension target already exists."
  exit 0
end

# 1. 拡張機能ターゲットの定義
extension_target = project.new_target(:app_extension, 'RunnerExtension', :ios, '16.0')
extension_target.product_type = 'com.apple.product-type.app-extension'

extension_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.h.k.portal.extension'
  config.build_settings['INFOPLIST_FILE'] = 'RunnerExtension/Info.plist'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
end

# 2. ソースファイルおよびリソースの紐付け
group = project.main_group.find_subpath('RunnerExtension', true)
group.set_source_tree('<group>')

swift_file = group.new_file('RunnerExtension/SafariExtensionHandler.swift')
extension_target.add_file_references([swift_file])

manifest_file = group.new_file('RunnerExtension/manifest.json')
content_file = group.new_file('RunnerExtension/content.js')
background_file = group.new_file('RunnerExtension/background.js') # 🟢 追加：HttpOnlyクッキー取得用

resources_phase = extension_target.resources_build_phase
resources_phase.add_file_reference(manifest_file)
resources_phase.add_file_reference(content_file)
resources_phase.add_file_reference(background_file) # 🟢 追加

# 3. SafariServices Framework のリンク設定
frameworks_phase = extension_target.frameworks_build_phase
sf_framework = project.frameworks_group.new_file('System/Library/Frameworks/SafariServices.framework')
sf_framework.source_tree = 'SDKROOT'
frameworks_phase.add_file_reference(sf_framework)

# 4. メインアプリ (Runner) への Embed (PlugIns フォルダへの同梱) 設定
main_target = project.targets.find { |t| t.name == 'Runner' }
main_target.add_dependency(extension_target)

embed_phase = main_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
unless embed_phase
  embed_phase = main_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end
embed_phase.add_file_reference(extension_target.product_reference, true)

project.save
puts "Successfully added RunnerExtension target to Xcode project."