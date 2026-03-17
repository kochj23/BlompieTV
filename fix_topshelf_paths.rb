#!/usr/bin/env ruby
# Fix Top Shelf file paths in BlompieTV project
# Created by Jordan Koch

require 'xcodeproj'

project_path = '/Volumes/Data/xcode/BlompieTV/BlompieTV.xcodeproj'
project = Xcodeproj::Project.open(project_path)

puts "Fixing Top Shelf file paths..."

topshelf_target = project.targets.find { |t| t.name == 'BlompieTVTopShelf' }

if topshelf_target
  topshelf_target.source_build_phase.files.each { |f| f.remove_from_project }
  puts "Cleared existing Top Shelf build phases"
end

topshelf_group = project.main_group.children.find { |c| c.name == 'BlompieTVTopShelf' }
topshelf_group.remove_from_project if topshelf_group

topshelf_group = project.main_group.new_group('BlompieTVTopShelf', 'BlompieTVTopShelf')

swift_ref = topshelf_group.new_file('ContentProvider.swift')
info_ref = topshelf_group.new_file('Info.plist')
entitlements_ref = topshelf_group.new_file('BlompieTVTopShelf.entitlements')

if topshelf_target
  topshelf_target.source_build_phase.add_file_reference(swift_ref)
  puts "Added files to Top Shelf target build phases"
end

project.save
puts "Top Shelf file paths fixed successfully!"
