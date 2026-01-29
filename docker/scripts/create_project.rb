#!/usr/bin/env ruby
# Script para crear un proyecto en GitLab

require 'json'

project_name        = ENV['PROJECT_NAME']
project_path        = ENV['PROJECT_PATH'] || project_name
description         = ENV['PROJECT_DESCRIPTION'] || ''
visibility          = ENV['PROJECT_VISIBILITY'] || 'private'
namespace_id        = ENV['PROJECT_NAMESPACE_ID']
project_config_json = ENV['PROJECT_CONFIG_JSON']

if project_name.nil? || project_name.empty?
  puts 'ERROR:PROJECT_NAME es requerido'
  exit 1
end

# Parsear configuración JSON si está disponible
config = {}
if project_config_json && !project_config_json.empty?
  begin
    config = JSON.parse(project_config_json)
  rescue JSON::ParserError => e
    # Si falla el parseo, continuar con valores por defecto
  end
end

# Mapear visibilidad
visibility_level = case visibility.downcase
                   when 'private' then 0
                   when 'internal' then 10
                   when 'public' then 20
                   else 0
                   end

# Obtener valores de configuración
init_readme = config.fetch('initialize_with_readme', false)
default_branch = config.fetch('default_branch', 'main')
issues_enabled = config.fetch('issues_enabled', true)
merge_requests_enabled = config.fetch('merge_requests_enabled', true)
wiki_enabled = config.fetch('wiki_enabled', true)
snippets_enabled = config.fetch('snippets_enabled', true)
container_registry_enabled = config.fetch('container_registry_enabled', true)
lfs_enabled = config.fetch('lfs_enabled', false)
shared_runners_enabled = config.fetch('shared_runners_enabled', true)
only_allow_merge_if_pipeline_succeeds = config.fetch('only_allow_merge_if_pipeline_succeeds', false)
only_allow_merge_if_all_discussions_are_resolved = config.fetch('only_allow_merge_if_all_discussions_are_resolved', false)
allow_merge_on_skipped_pipeline = config.fetch('allow_merge_on_skipped_pipeline', false)
remove_source_branch_after_merge = config.fetch('remove_source_branch_after_merge', true)
printing_merge_request_link_enabled = config.fetch('printing_merge_request_link_enabled', true)
ci_config_path = config.fetch('ci_config_path', '.gitlab-ci.yml')

begin
  root = User.find_by_username('root')
  org = root.organization || Organization.first
  
  namespace = nil
  if namespace_id && !namespace_id.empty? && namespace_id != 'nil' && namespace_id.to_i > 0
    namespace = Namespace.find(namespace_id.to_i)
  end
  
  # Verificar si el proyecto ya existe
  project_path_full = namespace ? "#{namespace.full_path}/#{project_path}" : project_path
  existing_project = Project.find_by_full_path(project_path_full)
  if existing_project
    puts "SUCCESS:#{existing_project.id}"
    exit 0
  end
  
  project = Project.new(
    name: project_name,
    path: project_path,
    description: description,
    visibility_level: visibility_level,
    namespace: namespace,
    creator: root,
    organization: org,
    default_branch: default_branch,
    issues_enabled: issues_enabled,
    merge_requests_enabled: merge_requests_enabled,
    wiki_enabled: wiki_enabled,
    snippets_enabled: snippets_enabled,
    container_registry_enabled: container_registry_enabled,
    lfs_enabled: lfs_enabled,
    shared_runners_enabled: shared_runners_enabled,
    only_allow_merge_if_pipeline_succeeds: only_allow_merge_if_pipeline_succeeds,
    only_allow_merge_if_all_discussions_are_resolved: only_allow_merge_if_all_discussions_are_resolved,
    allow_merge_on_skipped_pipeline: allow_merge_on_skipped_pipeline,
    remove_source_branch_after_merge: remove_source_branch_after_merge,
    printing_merge_request_link_enabled: printing_merge_request_link_enabled,
    ci_config_path: ci_config_path
  )
  
  if project.save
    # Crear el repositorio en disco siempre
    project.repository.create_if_not_exists

    # Inicializar con README si está configurado
    if init_readme
      begin
        project.repository.create_file(
          root,
          'README.md',
          "# #{project.name}\n\n#{project.description}",
          message: 'Add README',
          branch_name: default_branch
        )
      rescue => e
        # Ignorar errores al crear README
      end
    end

    puts "SUCCESS:#{project.id}"
    exit 0
  else
    error_msg = project.errors.full_messages.join('; ')
    if error_msg.include?('has already been taken')
      existing = Project.find_by_full_path(project_path_full)
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
