#!/usr/bin/env ruby
# Fix bundle identifiers for BlompieTV
# Created by Jordan Koch

require 'xcodeproj'

project_path = '/Volumes/Data/xcode/BlompieTV/BlompieTV.xcodeproj'
project = Xcodeproj::Project.open(project_path)

puts "Fixing bundle identifiers..."

main_target = project.targets.find { |t| t.name == 'BlompieTV' }
main_bundle_id = nil
if main_target
  main_target.build_configurations.each do |config|
    if config.name == 'Debug'
      main_bundle_id = config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
      puts "Main app bundle ID: #{main_bundle_id}"
      break
    end
  end
end

topshelf_target = project.targets.find { |t| t.name == 'BlompieTVTopShelf' }
if topshelf_target && main_bundle_id
  topshelf_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{main_bundle_id}.topshelf"
  end
  puts "Top Shelf bundle ID set to: #{main_bundle_id}.topshelf"
end

project.save
puts "Bundle identifiers fixed!"
