#!/usr/bin/env ruby
# Script para obtener el ID de un grupo por su path

group_path = ENV['GROUP_PATH']

if group_path.nil? || group_path.empty?
  puts 'ERROR:GROUP_PATH no especificado'
  exit 1
end

begin
  group = Group.find_by_path(group_path)
  if group
    puts group.id.to_s
    exit 0
  else
    puts 'nil'
    exit 1
  end
rescue => e
  puts "ERROR:#{e.message}"
  exit 1
end
