#!/usr/bin/env ruby
# Configure App Groups and entitlements for BlompieTV
# Created by Jordan Koch

require 'xcodeproj'

project_path = '/Volumes/Data/xcode/BlompieTV/BlompieTV.xcodeproj'
project = Xcodeproj::Project.open(project_path)

puts "Configuring App Groups for BlompieTV..."

# Configure main app target
main_target = project.targets.find { |t| t.name == 'BlompieTV' }
if main_target
  main_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'BlompieTV/BlompieTV.entitlements'
  end
  puts "Main app entitlements configured"
end

# Configure Top Shelf target
topshelf_target = project.targets.find { |t| t.name == 'BlompieTVTopShelf' }
if topshelf_target
  topshelf_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'BlompieTVTopShelf/BlompieTVTopShelf.entitlements'
  end
  puts "Top Shelf entitlements configured"
end

# Add TopShelfDataManager.swift to the project
blompietv_group = project.main_group.children.find { |c| c.name == 'BlompieTV' }
if blompietv_group && main_target
  existing = blompietv_group.files.find { |f| f.path&.include?('TopShelfDataManager.swift') }
  unless existing
    file_ref = blompietv_group.new_file('TopShelfDataManager.swift')
    main_target.source_build_phase.add_file_reference(file_ref)
    puts "TopShelfDataManager.swift added to project"
  end

  # Add entitlements
  existing_ent = blompietv_group.files.find { |f| f.path&.include?('entitlements') }
  unless existing_ent
    blompietv_group.new_file('BlompieTV/BlompieTV.entitlements')
    puts "Main app entitlements file added"
  end
end

topshelf_group = project.main_group.children.find { |c| c.name == 'BlompieTVTopShelf' }
if topshelf_group
  existing = topshelf_group.files.find { |f| f.path&.include?('entitlements') }
  unless existing
    topshelf_group.new_file('BlompieTVTopShelf/BlompieTVTopShelf.entitlements')
    puts "Top Shelf entitlements file added"
  end
end

project.save
puts "App Groups configuration completed for BlompieTV!"
