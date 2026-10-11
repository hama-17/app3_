require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

existing_target = project.targets.find { |t| t.name == 'RunnerExtension' }
if existing_target
  puts "RunnerExtension target already exists."
  exit 0
end

# 🟢 product_type を :app_extension として作成
extension_target = project.new_target(:app_extension, 'RunnerExtension', :ios, '16.0')
extension_target.product_type = 'com.apple.product-type.app-extension'

extension_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.h.k.portal.extension'
  config.build_settings['INFOPLIST_FILE'] = 'RunnerExtension/Info.plist'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
end

group = project.main_group.find_subpath('RunnerExtension', true)
group.set_source_tree('<group>')

swift_file = group.new_file('RunnerExtension/SafariExtensionHandler.swift')
extension_target.add_file_references([swift_file])

manifest_file = group.new_file('RunnerExtension/manifest.json')
content_file = group.new_file('RunnerExtension/content.js')
resources_phase = extension_target.resources_build_phase
resources_phase.add_file_reference(manifest_file)
resources_phase.add_file_reference(content_file)

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