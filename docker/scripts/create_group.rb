#!/usr/bin/env ruby
# Script para crear un grupo en GitLab

group_name = ENV['GROUP_NAME']
group_path = ENV['GROUP_PATH']
description = ENV['GROUP_DESCRIPTION'] || ''
visibility = ENV['GROUP_VISIBILITY'] || 'private'

if group_name.nil? || group_name.empty? || group_path.nil? || group_path.empty?
  puts 'ERROR:GROUP_NAME y GROUP_PATH son requeridos'
  exit 1
end

# Verificar si el grupo ya existe
existing_group = Group.find_by_path(group_path)
if existing_group
  puts "SUCCESS:#{existing_group.id}"
  exit 0
end

# Mapear visibilidad
visibility_level = case visibility.downcase
                   when 'private' then 0
                   when 'internal' then 10
                   when 'public' then 20
                   else 0
                   end

begin
  root = User.find_by_username('root')
  org = root.organization || Organization.first || Organization.create!(name: 'Default Organization', path: 'default-org', owner: root)
  
  group = Group.new(
    name: group_name,
    path: group_path,
    description: description,
    visibility_level: visibility_level,
    organization_id: org.id
  )
  
  if group.save
    puts "SUCCESS:#{group.id}"
    exit 0
  else
    error_msg = group.errors.full_messages.join('; ')
    if error_msg.include?('has already been taken')
      existing = Group.find_by_path(group_path)
      puts "SUCCESS:#{existing.id}"
      exit 0
    else
      puts "ERROR:#{error_msg}"
      exit 1
    end
  end
rescue => e
  puts "ERROR:Exception: #{e.message}"
  exit 1
end
