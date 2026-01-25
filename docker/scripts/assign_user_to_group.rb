#!/usr/bin/env ruby
# Script para asignar un usuario a un grupo en GitLab

user_id = ENV['USER_ID']
group_path = ENV['GROUP_PATH']
access_level = (ENV['ACCESS_LEVEL'] || '30').to_i

if user_id.nil? || user_id.empty? || group_path.nil? || group_path.empty?
  puts 'ERROR:USER_ID y GROUP_PATH son requeridos'
  exit 1
end

begin
  group = Group.find_by_path(group_path)
  unless group
    puts "ERROR:Grupo '#{group_path}' no encontrado"
    exit 1
  end
  
  user = User.find_by_id(user_id.to_i)
  unless user
    puts "ERROR:Usuario con ID #{user_id} no encontrado"
    exit 1
  end
  
  # Verificar si el usuario ya está en el grupo
  existing_member = group.members.find_by(user_id: user.id)
  if existing_member
    puts "SUCCESS:#{existing_member.id}"
    exit 0
  end
  
  # Crear la membresía
  member = group.members.build(user: user, access_level: access_level)
  if member.save
    puts "SUCCESS:#{member.id}"
    exit 0
  else
    error_msg = member.errors.full_messages.join('; ')
    puts "ERROR:#{error_msg}"
    exit 1
  end
rescue => e
  puts "ERROR:Exception: #{e.message}"
  exit 1
end
