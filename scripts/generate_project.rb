require 'xcodeproj'
require 'fileutils'
root = File.expand_path('..', __dir__)
Dir.chdir(root)
path = 'SideQuest.xcodeproj'
project = File.exist?(path) ? Xcodeproj::Project.open(path) : Xcodeproj::Project.new(path)
project.files.select { |file| file.path&.start_with?('iOS/') && !File.exist?(file.path) }.each(&:remove_from_project)
definitions = {
  'SideQuestCore' => [:framework, ['iOS/Core'], 'com.sidequest.core'],
  'SideQuest' => [:application, ['iOS/App', 'iOS/Shared'], 'com.sidequest.app'],
  'SideQuestMessages' => [:messages_extension, ['iOS/MessagesExtension', 'iOS/Shared'], 'com.sidequest.app.messages'],
  'SideQuestTests' => [:unit_test_bundle, ['iOS/Tests'], 'com.sidequest.tests'],
  'SideQuestUITests' => [:ui_test_bundle, ['iOS/UITests'], 'com.sidequest.uitests']
}
targets = {}
definitions.each do |name, (type, folders, bundle)|
  target = project.targets.find { |item| item.name == name } || project.new_target(type, name, :ios, '17.0')
  targets[name] = target
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => bundle, 'SWIFT_VERSION' => '5.0',
      'IPHONEOS_DEPLOYMENT_TARGET' => '17.0', 'TARGETED_DEVICE_FAMILY' => '1',
      'CODE_SIGN_STYLE' => 'Automatic', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'CURRENT_PROJECT_VERSION' => '1', 'MARKETING_VERSION' => '1.0',
      'SWIFT_EMIT_LOC_STRINGS' => 'YES', 'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES'
    })
    if name == 'SideQuestCore'
      config.build_settings.merge!('MACH_O_TYPE' => 'staticlib', 'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'SKIP_INSTALL' => 'YES')
    elsif name == 'SideQuest'
      config.build_settings.merge!('INFOPLIST_FILE' => 'iOS/App/Info.plist', 'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES')
      config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'iOS/Shared/SideQuest.entitlements'
    elsif name == 'SideQuestMessages'
      config.build_settings.merge!('INFOPLIST_FILE' => 'iOS/MessagesExtension/Info.plist', 'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'SKIP_INSTALL' => 'YES')
      config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'iOS/Shared/SideQuest.entitlements'
    elsif name == 'SideQuestTests'
      config.build_settings.merge!('TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/SideQuest.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SideQuest', 'BUNDLE_LOADER' => '$(TEST_HOST)')
    elsif name == 'SideQuestUITests'
      config.build_settings['TEST_TARGET_NAME'] = 'SideQuest'
    end
  end
  folders.each do |folder|
    group = project.main_group.find_subpath(folder, true)
    Dir.glob("#{folder}/**/*").select { |file| File.file?(file) && ['.swift', '.storyboard'].include?(File.extname(file)) }.sort.each do |file|
      ref = project.files.find { |item| item.path == file } || group.new_file(file)
      phase = file.end_with?('.swift') ? target.source_build_phase : target.resources_build_phase
      phase.add_file_reference(ref, true) unless phase.files_references.include?(ref)
    end
  end
end
['SideQuest', 'SideQuestMessages', 'SideQuestTests'].each do |name|
  target = targets[name]
  core = targets['SideQuestCore']
  target.add_dependency(core) unless target.dependencies.any? { |dep| dep.target == core }
  target.frameworks_build_phase.add_file_reference(core.product_reference, true) unless target.frameworks_build_phase.files_references.include?(core.product_reference)
end
app = targets['SideQuest']
extension = targets['SideQuestMessages']
app.add_dependency(extension) unless app.dependencies.any? { |dep| dep.target == extension }
embed = app.copy_files_build_phases.find { |phase| phase.name == 'Embed App Extensions' } || app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(extension.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] } unless embed.files_references.include?(extension.product_reference)
['SideQuestTests', 'SideQuestUITests'].each do |name|
  targets[name].add_dependency(app) unless targets[name].dependencies.any? { |dep| dep.target == app }
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(targets['SideQuestTests'])
scheme.add_test_target(targets['SideQuestUITests'])
scheme.test_action.code_coverage_enabled = true
scheme.save_as(path, 'SideQuest', true)
messages_scheme = Xcodeproj::XCScheme.new
messages_scheme.add_build_target(app)
messages_scheme.set_launch_target(extension)
messages_scheme.launch_action.xml_element.delete_element('BuildableProductRunnable')
messages_scheme.launch_action.xml_element.add_element(Xcodeproj::XCScheme::RemoteRunnable.new(extension, '1', 'com.apple.MobileSMS', '/Applications/MobileSMS.app').xml_element)
messages_scheme.save_as(path, 'SideQuestMessages', true)
puts "Updated #{path}"
