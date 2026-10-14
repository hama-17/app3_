require 'xcodeproj'
require 'fileutils'
require 'rexml/document'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 1. Entitlements (App Group) ファイル作成
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

File.write(File.join(entitlements_dir, 'RunnerExtension.entitlements'), entitlements_content)

# 2. RunnerExtension ターゲットの取得または作成
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

# 3. ソース・リソースファイルの紐付け
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

# 4. Frameworks 設定
frameworks_phase = extension_target.frameworks_build_phase
sf_framework = project.frameworks_group.find_file_by_path('System/Library/Frameworks/SafariServices.framework') || project.frameworks_group.new_file('System/Library/Frameworks/SafariServices.framework')
sf_framework.source_tree = 'SDKROOT'
frameworks_phase.add_file_reference(sf_framework)

# 5. ビルド依存関係 (Target Dependency) と Embed フェーズの設定
main_target = project.targets.find { |t| t.name == 'Runner' }

unless main_target.dependencies.any? { |d| d.target == extension_target }
  main_target.add_dependency(extension_target)
end

embed_phase = main_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
unless embed_phase
  embed_phase = main_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end

embed_phase.files_references.each { |f| embed_phase.remove_file_reference(f) if f == extension_target.product_reference }
build_file = embed_phase.add_file_reference(extension_target.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy'] }

project.save

# 🟢 6. 【最重要】Xcode Scheme (Runner.xcscheme) へ RunnerExtension を強制作入
scheme_path = 'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme'
if File.exist?(scheme_path)
  doc = REXML::Document.new(File.read(scheme_path))
  build_action_entries = REXML::XPath.first(doc, "//BuildAction/BuildActionEntries")

  if build_action_entries
    already_added = false
    build_action_entries.each_element('BuildActionEntry') do |entry|
      ref = entry.elements['BuildableReference']
      if ref && ref.attributes['BlueprintName'] == 'RunnerExtension'
        already_added = true
        break
      end
    end

    unless already_added
      entry_xml = <<~XML
        <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
           <BuildableReference
              BuildableIdentifier = "primary"
              BlueprintIdentifier = "#{extension_target.uuid}"
              BuildableName = "RunnerExtension.appex"
              BlueprintName = "RunnerExtension"
              ReferencedContainer = "container:Runner.xcodeproj">
           </BuildableReference>
        </BuildActionEntry>
      XML
      entry_doc = REXML::Document.new(entry_xml)
      build_action_entries.add_element(entry_doc.root)

      File.open(scheme_path, 'w') do |f|
        doc.write(f, 2)
      end
      puts "Successfully injected RunnerExtension into Runner.xcscheme"
    end
  end
end

puts "Successfully configured RunnerExtension target and scheme in project."