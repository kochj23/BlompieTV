#!/usr/bin/env ruby
# Add BlompieTV Top Shelf extension target to Xcode project
# Created by Jordan Koch

require 'xcodeproj'

project_path = '/Volumes/Data/xcode/BlompieTV/BlompieTV.xcodeproj'
project = Xcodeproj::Project.open(project_path)

puts "Adding BlompieTV Top Shelf extension target..."

# Check if target already exists
existing_target = project.targets.find { |t| t.name == 'BlompieTVTopShelf' }
if existing_target
  puts "Top Shelf target already exists, removing and recreating..."
  existing_target.remove_from_project
end

# Create TV Top Shelf extension target
topshelf_target = project.new_target(:tv_extension, 'BlompieTVTopShelf', :tvos, '17.0')

# Set up build settings
topshelf_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.jordankoch.blompietv.topshelf'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['INFOPLIST_FILE'] = 'BlompieTVTopShelf/Info.plist'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = 'QRRCB8HB3W'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '3'
  config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'

  if config.name == 'Debug'
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
  else
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
    config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
  end
end

# Create group and add files
topshelf_group = project.main_group.new_group('BlompieTVTopShelf', 'BlompieTVTopShelf')

swift_file_ref = topshelf_group.new_file('BlompieTVTopShelf/ContentProvider.swift')
topshelf_target.source_build_phase.add_file_reference(swift_file_ref)

topshelf_group.new_file('BlompieTVTopShelf/Info.plist')

# Add TVServices framework
tvservices_ref = project.frameworks_group.new_file('System/Library/Frameworks/TVServices.framework', :sdk_root)
topshelf_target.frameworks_build_phase.add_file_reference(tvservices_ref)

# Embed in main app
main_target = project.targets.find { |t| t.name == 'BlompieTV' }
if main_target
  embed_phase = main_target.build_phases.find { |p| p.class == Xcodeproj::Project::Object::PBXCopyFilesBuildPhase && p.name == 'Embed App Extensions' }

  unless embed_phase
    embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
    embed_phase.name = 'Embed App Extensions'
    embed_phase.dst_subfolder_spec = '13'
    embed_phase.dst_path = ''
    main_target.build_phases << embed_phase
  end

  topshelf_product = topshelf_target.product_reference
  build_file = embed_phase.add_file_reference(topshelf_product)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

  main_target.add_dependency(topshelf_target)
  puts "Top Shelf embedded in main app target"
end

project.save
puts "BlompieTV Top Shelf extension target added successfully!"
