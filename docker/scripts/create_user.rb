#!/usr/bin/env ruby
# Script para crear un usuario en GitLab

username          = ENV['USER_USERNAME']
email             = ENV['USER_EMAIL']
password          = ENV['USER_PASSWORD']
name              = ENV['USER_NAME'] || username
is_admin          = ENV['USER_IS_ADMIN'] == 'true'
skip_confirmation = ENV['USER_SKIP_CONFIRMATION'] != 'false'

if username.nil? || username.empty? || email.nil? || email.empty? || password.nil? || password.empty?
  puts 'ERROR:USER_USERNAME, USER_EMAIL y USER_PASSWORD son requeridos'
  exit 1
end

# Verificar si el usuario ya existe
existing_user = User.find_by_username(username)
if existing_user
  puts "SUCCESS:#{existing_user.id}"
  exit 0
end

begin
  root = User.find_by_username('root')
  org = root.organization || Organization.first
  
  user = User.new(
    username: username,
    email: email,
    password: password,
    name: name,
    admin: is_admin,
    skip_confirmation: skip_confirmation,
    organization: org
  )
  
  # Crear namespace personal para el usuario
  user.build_namespace(
    name: username,
    path: username,
    owner: user,
    type: 'User',
    organization: org
  )
  
  if user.save
    puts "SUCCESS:#{user.id}"
    exit 0
  else
    error_msg = user.errors.full_messages.join('; ')
    if error_msg.include?('has already been taken')
      existing = User.find_by_username(username)
      puts "SUCCESS:#{existing.id}"
      exit 0
    else
      puts "ERROR:#{error_msg}"
      exit 1
    end
  end
rescue => e
  puts "ERROR:Exception: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
