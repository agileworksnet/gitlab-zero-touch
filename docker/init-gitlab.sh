#!/bin/bash
set -e

# =============================================================================
# Script de inicialización de GitLab
# =============================================================================
# Este script configura GitLab después del primer inicio:
# - Espera a que GitLab esté disponible
# - Obtiene la contraseña inicial de root
# - Crea un token de acceso personal para automatización
#
# Variables de entorno requeridas:
# - GITLAB_URL: URL interna de GitLab
# - CONFIG_FILE: Ruta al archivo de configuración JSON
# =============================================================================

# Validar variables requeridas
if [ -z "$GITLAB_URL" ]; then
    echo "[ERROR] GITLAB_URL no está definida" >&2
    exit 1
fi

if [ -z "$CONFIG_FILE" ]; then
    echo "[ERROR] CONFIG_FILE no está definida" >&2
    exit 1
fi

MAX_WAIT_SECONDS=300
RUNNER_CMD="gitlab-rails runner"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# =============================================================================
# Instalar dependencias necesarias
# =============================================================================
install_dependencies() {
    # Solo instalar dependencias si estamos fuera del contenedor de GitLab
    if [ ! -f /.dockerenv ] && [ -z "${DOCKER_CONTAINER}" ]; then
        log_info "Instalando dependencias necesarias..."

        # Instalar curl si no está disponible
        if ! command -v curl &> /dev/null; then
            apk add --no-cache curl
        fi

        # Instalar docker-cli si no está disponible
        if ! command -v docker &> /dev/null; then
            apk add --no-cache docker-cli
        fi

        # Instalar jq para procesar JSON si no está disponible
        if ! command -v jq &> /dev/null; then
            apk add --no-cache jq
        fi
    else
        # Dentro del contenedor, jq debería estar disponible o podemos usar el que viene con GitLab
        # curl y gitlab-rails ya están disponibles
        log_info "Ejecutando dentro del contenedor de GitLab, dependencias ya disponibles"
    fi
}

# =============================================================================
# Esperar a que GitLab esté disponible
# =============================================================================
wait_for_gitlab() {
    log_info "Esperando a que GitLab esté disponible en ${GITLAB_URL}..."

    local elapsed=0
    while [ $elapsed -lt $MAX_WAIT_SECONDS ]; do
        # Si estamos dentro del contenedor, usar curl directamente
        if [ -f /.dockerenv ] || [ -n "${DOCKER_CONTAINER}" ]; then
            if curl -s -f "http://localhost:80/-/health" 2>/dev/null | grep -q "GitLab OK"; then
                log_info "GitLab está disponible"
                return 0
            fi
        else
            # Si estamos fuera, usar docker exec
            if docker exec "${CONTAINER_NAME}" curl -s -f "http://localhost:80/-/health" 2>/dev/null | grep -q "GitLab OK"; then
                log_info "GitLab está disponible"
                return 0
            fi
            
            # Alternativa: verificar que el contenedor esté saludable según Docker
            if docker inspect "${CONTAINER_NAME}" --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; then
                log_info "GitLab está disponible (contenedor saludable)"
                return 0
            fi
        fi

        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_error "GitLab no está disponible después de ${MAX_WAIT_SECONDS} segundos"
    return 1
}

# =============================================================================
# Obtener contraseña inicial de root
# =============================================================================
get_root_password() {
    if [ -n "$GITLAB_ROOT_PASSWORD" ]; then
        log_info "Usando contraseña de root proporcionada"
        echo "$GITLAB_ROOT_PASSWORD"
        return 0
    fi

    log_info "Obteniendo contraseña inicial de root desde el contenedor..."

    local password
    if [ -f /.dockerenv ] || [ -n "${DOCKER_CONTAINER}" ]; then
        # Estamos dentro del contenedor
        password=$(cat /etc/gitlab/initial_root_password 2>/dev/null | grep "Password:" | awk '{print $2}')
    else
        # Estamos fuera, usar docker exec
        password=$(docker exec "${CONTAINER_NAME}" cat /etc/gitlab/initial_root_password 2>/dev/null | grep "Password:" | awk '{print $2}')
    fi

    if [ -z "$password" ]; then
        log_error "No se pudo obtener la contraseña inicial de root"
        log_warn "Puedes establecerla manualmente con: GITLAB_ROOT_PASSWORD=<password>"
        return 1
    fi

    echo "$password"
}

# =============================================================================
# Crear token de acceso personal
# =============================================================================
create_access_token() {
    log_info "Creando token de acceso personal..."

    local token
    token=$(${RUNNER_CMD} "
        user = User.find_by_username('root')
        if user.nil?
          puts 'ERROR: Usuario root no encontrado'
          exit 1
        end
        
        # Eliminar token existente si existe
        existing_token = user.personal_access_tokens.find_by(name: 'automation-token')
        existing_token&.revoke!
        
        # Crear nuevo token
        token = user.personal_access_tokens.create!(
            name: 'automation-token',
            scopes: ['api', 'read_repository', 'write_repository', 'read_user', 'sudo'],
            expires_at: 365.days.from_now
        )
        puts token.token
    " 2>/dev/null)

    if [ -z "$token" ] || echo "$token" | grep -q "ERROR"; then
        log_warn "No se pudo crear token automáticamente"
        log_warn "Crea un token manualmente en: ${GITLAB_URL}/-/user_settings/personal_access_tokens"
        return 1
    fi

    echo "$token"
}

# =============================================================================
# Leer y validar archivo de configuración JSON
# =============================================================================
read_config() {
    local config_path="$1"
    
    if [ ! -f "$config_path" ]; then
        log_info "Archivo de configuración no encontrado: ${config_path}"
        log_info "La inicialización continuará sin configuración personalizada"
        return 1
    fi

    if ! jq empty "$config_path" 2>/dev/null; then
        log_error "El archivo JSON no es válido: ${config_path}"
        return 1
    fi

    echo "$config_path"
}

# =============================================================================
# Obtener ID de grupo por nombre o path usando gitlab-rails
# =============================================================================
get_group_id() {
    local token="$1"
    local group_path="$2"

    local group_path_escaped
    group_path_escaped=$(printf '%s' "$group_path" | sed "s/'/\\\\'/g")
    local group_id
    group_id=$(GROUP_PATH="${group_path_escaped}" ${RUNNER_CMD} "/opt/gitlab/init-scripts/get_group_id.rb" 2>/dev/null | tail -1)

    if [ -n "$group_id" ] && [ "$group_id" != "null" ] && [ "$group_id" != "nil" ] && ! echo "$group_id" | grep -q "^ERROR:"; then
        echo "$group_id"
        return 0
    fi

    return 1
}

# =============================================================================
# Crear grupo usando gitlab-rails (más confiable que API)
# =============================================================================
create_group() {
    local token="$1"
    local group_name="$2"
    local group_path="$3"
    local description="$4"
    local visibility="$5"

    log_info "Creando grupo '${group_name}' (${group_path})..."

    # Escapar valores para variables de entorno
    local group_name_escaped
    group_name_escaped=$(printf '%s' "$group_name" | sed "s/'/\\\\'/g")
    local group_path_escaped
    group_path_escaped=$(printf '%s' "$group_path" | sed "s/'/\\\\'/g")
    local description_escaped
    description_escaped=$(printf '%s' "$description" | sed "s/'/\\\\'/g")

    local result
    result=$(GROUP_NAME="${group_name_escaped}" \
        GROUP_PATH="${group_path_escaped}" \
        GROUP_DESCRIPTION="${description_escaped}" \
        GROUP_VISIBILITY="${visibility}" \
        ${RUNNER_CMD} "/opt/gitlab/init-scripts/create_group.rb" 2>/dev/null | tail -1)

    if echo "$result" | grep -q "^SUCCESS:"; then
        log_info "Grupo '${group_name}' creado correctamente"
        return 0
    elif echo "$result" | grep -q "^ERROR:"; then
        local error_msg
        error_msg=$(echo "$result" | sed 's/^ERROR://')
        if echo "$error_msg" | grep -q "has already been taken"; then
            log_warn "El grupo '${group_path}' ya existe"
            return 0
        else
            log_error "Error creando grupo '${group_name}': ${error_msg}"
            return 1
        fi
    else
        log_error "Error desconocido creando grupo '${group_name}'"
        return 1
    fi

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "201" ]; then
        log_info "Grupo '${group_name}' creado correctamente"
        return 0
    elif [ "$http_code" = "400" ]; then
        local error_msg
        error_msg=$(echo "$body" | jq -r '.message // .error // empty' 2>/dev/null || echo "$body")
        if echo "$error_msg" | grep -q "has already been taken"; then
            log_warn "El grupo '${group_path}' ya existe"
            return 0
        else
            log_error "Error creando grupo '${group_name}' (HTTP ${http_code}): ${error_msg}"
            return 1
        fi
    else
        local error_msg
        error_msg=$(echo "$body" | jq -r '.message // .error // empty' 2>/dev/null || echo "$body")
        log_error "Error creando grupo '${group_name}' (HTTP ${http_code}): ${error_msg}"
        return 1
    fi
}

# =============================================================================
# Crear grupos desde JSON
# =============================================================================
create_groups_from_config() {
    local token="$1"
    local config_file="$2"

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    local groups_count
    groups_count=$(jq '.groups | length' "$config_file" 2>/dev/null || echo "0")

    if [ "$groups_count" = "0" ] || [ -z "$groups_count" ]; then
        log_info "No hay grupos para crear en la configuración"
        return 0
    fi

    log_info "Procesando ${groups_count} grupo(s) desde configuración..."

    local created=0
    local skipped=0
    local failed=0
    local i=0

    while [ $i -lt "$groups_count" ]; do
        local current=$((i + 1))
        local group_name
        group_name=$(jq -r ".groups[${i}].name" "$config_file")
        local group_path
        group_path=$(jq -r ".groups[${i}].path // .groups[${i}].name" "$config_file")
        local description
        description=$(jq -r ".groups[${i}].description // \"\"" "$config_file")
        local visibility
        visibility=$(jq -r ".groups[${i}].visibility // \"private\"" "$config_file")

        log_info "[${current}/${groups_count}] Procesando grupo '${group_name}'..."

        if create_group "$token" "$group_name" "$group_path" "$description" "$visibility"; then
            created=$((created + 1))
            log_info "[${current}/${groups_count}] ✓ Grupo '${group_name}' completado"
        else
            local exit_code=$?
            if [ $exit_code -eq 0 ]; then
                skipped=$((skipped + 1))
            else
                failed=$((failed + 1))
                log_error "[${current}/${groups_count}] ✗ Grupo '${group_name}' falló"
            fi
        fi

        i=$((i + 1))
    done

    log_info "Resumen grupos: ${created} creados, ${skipped} omitidos, ${failed} fallidos (total: ${groups_count})"
}

# =============================================================================
# Crear usuario usando gitlab-rails
# =============================================================================
create_user() {
    local token="$1"
    local username="$2"
    local email="$3"
    local password="$4"
    local name="$5"
    local is_admin="${6:-false}"
    local skip_confirmation="${7:-true}"

    # Verificar si el usuario ya existe usando get_group_id (reutilizamos el script)
    # Nota: get_group_id busca grupos, pero podemos crear un script similar para usuarios
    # Por ahora, verificamos directamente
    local username_escaped
    username_escaped=$(printf '%s' "$username" | sed "s/'/\\\\'/g")
    local existing_user
    existing_user=$(${RUNNER_CMD} "
        user = User.find_by_username('${username_escaped}')
        puts user ? user.id : 'nil'
    " 2>/dev/null | tail -1)

    if [ -n "$existing_user" ] && [ "$existing_user" != "nil" ]; then
        log_warn "El usuario '${username}' ya existe, saltando creación"
        echo "$existing_user"
        return 0
    fi

    log_info "Creando usuario '${username}'..."

    # Escapar valores para variables de entorno
    local username_escaped
    username_escaped=$(printf '%s' "$username" | sed "s/'/\\\\'/g")
    local email_escaped
    email_escaped=$(printf '%s' "$email" | sed "s/'/\\\\'/g")
    local password_escaped
    password_escaped=$(printf '%s' "$password" | sed "s/'/\\\\'/g")
    local name_escaped
    name_escaped=$(printf '%s' "$name" | sed "s/'/\\\\'/g")

    local result
    result=$(USER_USERNAME="${username_escaped}" \
        USER_EMAIL="${email_escaped}" \
        USER_PASSWORD="${password_escaped}" \
        USER_NAME="${name_escaped}" \
        USER_IS_ADMIN="${is_admin}" \
        USER_SKIP_CONFIRMATION="${skip_confirmation}" \
        ${RUNNER_CMD} "/opt/gitlab/init-scripts/create_user.rb" 2>/dev/null | tail -1)

    if echo "$result" | grep -q "^SUCCESS:"; then
        local user_id
        user_id=$(echo "$result" | sed 's/^SUCCESS://')
        log_info "Usuario '${username}' creado correctamente (ID: ${user_id})"
        echo "$user_id"
        return 0
    elif echo "$result" | grep -q "^ERROR:"; then
        local error_msg
        error_msg=$(echo "$result" | sed 's/^ERROR://')
        if echo "$error_msg" | grep -q "has already been taken"; then
            log_warn "El usuario '${username}' ya existe"
            # Buscar usuario directamente
            existing_user=$(${RUNNER_CMD} "
                user = User.find_by_username('${username_escaped}')
                puts user ? user.id : 'nil'
            " 2>/dev/null | tail -1)
            echo "$existing_user"
            return 0
        else
            log_error "Error creando usuario '${username}': ${error_msg}"
            return 1
        fi
    else
        log_error "Error desconocido creando usuario '${username}'"
        return 1
    fi
}

# =============================================================================
# Crear usuarios desde JSON
# =============================================================================
create_users_from_config() {
    local token="$1"
    local config_file="$2"

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    local users_count
    users_count=$(jq '.users | length' "$config_file" 2>/dev/null || echo "0")

    if [ "$users_count" = "0" ] || [ -z "$users_count" ]; then
        log_info "No hay usuarios para crear en la configuración"
        return 0
    fi

    log_info "Procesando ${users_count} usuario(s) desde configuración..."

    local created=0
    local skipped=0
    local failed=0
    local i=0

    while [ $i -lt "$users_count" ]; do
        local current=$((i + 1))
        local username
        username=$(jq -r ".users[${i}].username" "$config_file")
        local email
        email=$(jq -r ".users[${i}].email" "$config_file")
        local password
        password=$(jq -r ".users[${i}].password" "$config_file")
        local name
        name=$(jq -r ".users[${i}].name // .users[${i}].username" "$config_file")
        local is_admin
        is_admin=$(jq -r ".users[${i}].is_admin // false" "$config_file")
        local skip_confirmation
        skip_confirmation=$(jq -r ".users[${i}].skip_confirmation // true" "$config_file")

        log_info "[${current}/${users_count}] Procesando usuario '${username}'..."

        local user_id
        user_id=$(create_user "$token" "$username" "$email" "$password" "$name" "$is_admin" "$skip_confirmation" 2>&1)
        local exit_code=$?

        if [ $exit_code -eq 0 ] && [ -n "$user_id" ] && [ "$user_id" != "null" ] && [ "$user_id" != "nil" ]; then
            created=$((created + 1))
            log_info "[${current}/${users_count}] ✓ Usuario '${username}' completado (ID: ${user_id})"
        elif echo "$user_id" | grep -q "ya existe"; then
            skipped=$((skipped + 1))
            log_info "[${current}/${users_count}] ⊙ Usuario '${username}' ya existe, omitido"
        else
            failed=$((failed + 1))
            log_error "[${current}/${users_count}] ✗ Usuario '${username}' falló"
        fi

        i=$((i + 1))
    done

    log_info "Resumen usuarios: ${created} creados, ${skipped} omitidos, ${failed} fallidos (total: ${users_count})"
}

# =============================================================================
# Asignar usuario a grupo
# =============================================================================
assign_user_to_group() {
    local token="$1"
    local user_id="$2"
    local group_path="$3"
    local access_level="${4:-30}"

    # Escapar valores para variables de entorno
    local group_path_escaped
    group_path_escaped=$(printf '%s' "$group_path" | sed "s/'/\\\\'/g")

    log_info "Asignando usuario ID ${user_id} al grupo '${group_path}'..."

    local result
    result=$(USER_ID="${user_id}" \
        GROUP_PATH="${group_path_escaped}" \
        ACCESS_LEVEL="${access_level}" \
        ${RUNNER_CMD} "/opt/gitlab/init-scripts/assign_user_to_group.rb" 2>/dev/null | tail -1)

    if echo "$result" | grep -q "^SUCCESS:"; then
        log_info "Usuario asignado al grupo '${group_path}' correctamente"
        return 0
    elif echo "$result" | grep -q "^ERROR:"; then
        local error_msg
        error_msg=$(echo "$result" | sed 's/^ERROR://')
        if echo "$error_msg" | grep -q "ya está en el grupo\|already.*member"; then
            log_warn "Usuario ya está en el grupo '${group_path}'"
            return 0
        else
            log_warn "Error asignando usuario al grupo '${group_path}': ${error_msg}"
            return 1
        fi
    else
        log_warn "Error desconocido asignando usuario al grupo '${group_path}'"
        return 1
    fi
}

# =============================================================================
# Asignar usuarios a grupos desde JSON
# =============================================================================
assign_users_to_groups_from_config() {
    local token="$1"
    local config_file="$2"

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    local users_count
    users_count=$(jq '.users | length' "$config_file" 2>/dev/null || echo "0")

    if [ "$users_count" = "0" ] || [ -z "$users_count" ]; then
        log_info "No hay usuarios para asignar a grupos"
        return 0
    fi

    log_info "Asignando usuarios a grupos desde configuración..."

    local total_assignments=0
    local successful=0
    local skipped=0
    local failed=0
    local i=0

    while [ $i -lt "$users_count" ]; do
        local username
        username=$(jq -r ".users[${i}].username" "$config_file")
        local groups
        groups=$(jq -r ".users[${i}].groups // []" "$config_file")

        if [ "$groups" != "[]" ] && [ -n "$groups" ]; then
            # Obtener ID del usuario usando gitlab-rails
            local username_escaped
            username_escaped=$(printf '%s' "$username" | sed "s/'/\\\\'/g")
            local user_id
            user_id=$(${RUNNER_CMD} "
                user = User.find_by_username('${username_escaped}')
                puts user ? user.id : 'nil'
            " 2>/dev/null | tail -1)

            if [ -n "$user_id" ] && [ "$user_id" != "null" ] && [ "$user_id" != "nil" ]; then
                # Asignar a cada grupo
                local groups_count
                groups_count=$(echo "$groups" | jq 'length')
                local j=0
                while [ $j -lt "$groups_count" ]; do
                    local group_path
                    group_path=$(echo "$groups" | jq -r ".[${j}]")
                    total_assignments=$((total_assignments + 1))
                    
                    log_info "Asignando '${username}' al grupo '${group_path}'..."
                    
                    if assign_user_to_group "$token" "$user_id" "$group_path"; then
                        successful=$((successful + 1))
                        log_info "✓ '${username}' asignado a '${group_path}'"
                    else
                        local exit_code=$?
                        if [ $exit_code -eq 0 ]; then
                            skipped=$((skipped + 1))
                            log_info "⊙ '${username}' ya está en '${group_path}', omitido"
                        else
                            failed=$((failed + 1))
                            log_error "✗ Error asignando '${username}' a '${group_path}'"
                        fi
                    fi
                    j=$((j + 1))
                done
            else
                log_warn "Usuario '${username}' no encontrado, saltando asignaciones"
            fi
        fi

        i=$((i + 1))
    done

    log_info "Resumen asignaciones: ${successful} exitosas, ${skipped} omitidas, ${failed} fallidas (total: ${total_assignments})"
}

# =============================================================================
# Crear proyecto
# =============================================================================
create_project() {
    local token="$1"
    local project_name="$2"
    local project_path="$3"
    local description="$4"
    local visibility="$5"
    local group_path="$6"
    local config_json="$7"

    # Construir namespace_id si hay grupo
    local namespace_id="null"
    if [ -n "$group_path" ] && [ "$group_path" != "null" ]; then
        namespace_id=$(get_group_id "$token" "$group_path")
        if [ -z "$namespace_id" ] || [ "$namespace_id" = "null" ]; then
            log_warn "Grupo '${group_path}' no encontrado para proyecto '${project_name}', creando grupo automáticamente..."
            create_group "$token" "$group_path" "$group_path" "Grupo creado automáticamente para proyecto ${project_name}" "${visibility:-private}" || true
            namespace_id=$(get_group_id "$token" "$group_path")
        fi
    fi

    # Verificar si el proyecto ya existe usando gitlab-rails
    local project_path_full
    if [ -n "$group_path" ] && [ "$group_path" != "null" ] && [ -n "$namespace_id" ] && [ "$namespace_id" != "null" ]; then
        project_path_full="${group_path}/${project_path}"
    else
        project_path_full="$project_path"
    fi

    # Verificar si el proyecto ya existe (el script Ruby lo hace internamente, pero lo verificamos aquí también)
    local project_path_full_escaped
    project_path_full_escaped=$(printf '%s' "$project_path_full" | sed "s/'/\\\\'/g")
    local existing_project
    existing_project=$(${RUNNER_CMD} "
        project = Project.find_by_full_path('${project_path_full_escaped}')
        puts project ? project.id : 'nil'
    " 2>/dev/null | tail -1)

    if [ -n "$existing_project" ] && [ "$existing_project" != "nil" ] && [ "$existing_project" != "null" ]; then
        log_warn "El proyecto '${project_path_full}' ya existe, saltando creación"
        return 0
    fi

    log_info "Creando proyecto '${project_name}' (${project_path_full})..."

    # Mapear visibilidad a nivel de visibilidad de GitLab
    local visibility_level
    case "$visibility" in
        "private")
            visibility_level="0"
            ;;
        "internal")
            visibility_level="10"
            ;;
        "public")
            visibility_level="20"
            ;;
        *)
            visibility_level="0"
            ;;
    esac

    # Extraer opciones del JSON
    local init_readme
    init_readme=$(echo "$config_json" | jq -r '.initialize_with_readme // true')
    local issues
    issues=$(echo "$config_json" | jq -r '.issues_enabled // true')
    local mr
    mr=$(echo "$config_json" | jq -r '.merge_requests_enabled // true')
    local wiki
    wiki=$(echo "$config_json" | jq -r '.wiki_enabled // true')
    local snippets
    snippets=$(echo "$config_json" | jq -r '.snippets_enabled // true')
    local registry
    registry=$(echo "$config_json" | jq -r '.container_registry_enabled // true')
    local lfs
    lfs=$(echo "$config_json" | jq -r '.lfs_enabled // false')
    local runners
    runners=$(echo "$config_json" | jq -r '.shared_runners_enabled // true')
    local merge_pipeline
    merge_pipeline=$(echo "$config_json" | jq -r '.only_allow_merge_if_pipeline_succeeds // false')
    local merge_discussions
    merge_discussions=$(echo "$config_json" | jq -r '.only_allow_merge_if_all_discussions_are_resolved // false')
    local merge_skipped
    merge_skipped=$(echo "$config_json" | jq -r '.allow_merge_on_skipped_pipeline // false')
    local remove_branch
    remove_branch=$(echo "$config_json" | jq -r '.remove_source_branch_after_merge // true')
    local print_link
    print_link=$(echo "$config_json" | jq -r '.printing_merge_request_link_enabled // true')
    local branch
    branch=$(echo "$config_json" | jq -r '.default_branch // "main"')
    local ci_path
    ci_path=$(echo "$config_json" | jq -r '.ci_config_path // ".gitlab-ci.yml"')

    # Escapar el JSON para pasarlo como variable de entorno
    local config_json_escaped
    config_json_escaped=$(printf '%s' "$config_json" | sed 's/"/\\"/g' | sed "s/'/\\\\'/g")
    
    # Asegurar que namespace_id sea un número válido o nil
    local ns_id_for_ruby
    if [ -n "$namespace_id" ] && [ "$namespace_id" != "null" ] && [ "$namespace_id" != "nil" ] && [ "$namespace_id" -gt 0 ] 2>/dev/null; then
        ns_id_for_ruby="$namespace_id"
    else
        ns_id_for_ruby=""
    fi
    
    # Ejecutar script Ruby con timeout de 120 segundos
    log_info "Ejecutando script Ruby para crear proyecto..."
    local result
    result=$(timeout 120 env PROJECT_NAME="${project_name}" \
        PROJECT_PATH="${project_path}" \
        PROJECT_DESCRIPTION="${description}" \
        PROJECT_VISIBILITY="${visibility}" \
        PROJECT_NAMESPACE_ID="${ns_id_for_ruby}" \
        PROJECT_CONFIG_JSON="${config_json_escaped}" \
        ${RUNNER_CMD} "/opt/gitlab/init-scripts/create_project.rb" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        log_error "Timeout creando proyecto '${project_name}' - el comando tardó más de 120 segundos"
        log_error "Debug: namespace_id='${namespace_id}', ns_id_for_ruby='${ns_id_for_ruby}'"
        log_error "Primeras líneas de la salida:"
        echo "$result" | head -5 | while IFS= read -r line; do
            log_error "  $line"
        done
        return 1
    fi
    
    log_info "Script Ruby completado (exit_code=$exit_code)"
    
    # Limpiar y procesar resultado
    local result_clean
    result_clean=$(echo "$result" | grep -E "^(SUCCESS|ERROR):" | head -1 | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Si no hay resultado limpio, usar el original
    if [ -z "$result_clean" ]; then
        result_clean=$(echo "$result" | tail -1 | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
    
    result="$result_clean"

    if [ -z "$result" ] || [ "$result" = "" ]; then
        log_error "Error desconocido creando proyecto '${project_name}' - comando no devolvió salida"
        log_error "Debug: namespace_id='${namespace_id}', ns_id_for_ruby='${ns_id_for_ruby}'"
        log_error "Salida completa del comando (primeras 10 líneas):"
        echo "$result" | head -10 | while IFS= read -r line; do
            log_error "  $line"
        done
        return 1
    elif echo "$result" | grep -q "^SUCCESS:"; then
        log_info "Proyecto '${project_name}' creado correctamente"
        return 0
    elif echo "$result" | grep -q "^ERROR:"; then
        local error_msg
        error_msg=$(echo "$result" | sed 's/^ERROR://')
        if echo "$error_msg" | grep -q "has already been taken"; then
            log_warn "El proyecto '${project_path_full}' ya existe"
            return 0
        else
            log_error "Error creando proyecto '${project_name}': ${error_msg}"
            return 1
        fi
    else
        log_error "Error desconocido creando proyecto '${project_name}'"
        if [ -z "$result" ] || [ "$result" = "" ]; then
            log_error "El comando no devolvió ninguna salida (resultado vacío o comando falló)"
        else
            log_error "Salida del comando: '${result}'"
        fi
        log_error "Debug: namespace_id='${namespace_id}', ns_id_for_ruby='${ns_id_for_ruby}'"
        return 1
    fi
}

# =============================================================================
# Verificar que grupos existan antes de crear proyectos
# =============================================================================
validate_groups_for_projects() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    local projects_count
    projects_count=$(jq '.projects | length' "$config_file" 2>/dev/null || echo "0")

    if [ "$projects_count" = "0" ]; then
        return 0
    fi

    log_info "Validando que los grupos referenciados en proyectos existan..."

    local missing_groups=0
    local i=0

    while [ $i -lt "$projects_count" ]; do
        local group_path
        group_path=$(jq -r ".projects[${i}].group // null" "$config_file")
        local project_name
        project_name=$(jq -r ".projects[${i}].name" "$config_file")

        if [ -n "$group_path" ] && [ "$group_path" != "null" ]; then
            local group_exists
            group_exists=$(${RUNNER_CMD} "
                group = Group.find_by_path('${group_path}')
                puts group ? 'exists' : 'missing'
            " 2>/dev/null | tail -1)

            if [ "$group_exists" != "exists" ]; then
                log_warn "Grupo '${group_path}' referenciado por proyecto '${project_name}' no existe"
                missing_groups=$((missing_groups + 1))
            fi
        fi

        i=$((i + 1))
    done

    if [ $missing_groups -gt 0 ]; then
        log_warn "Se encontraron ${missing_groups} grupo(s) faltante(s). Se intentarán crear automáticamente."
    else
        log_info "✓ Todos los grupos referenciados existen"
    fi
}

# =============================================================================
# Crear proyectos desde JSON
# =============================================================================
create_projects_from_config() {
    local token="$1"
    local config_file="$2"

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    local projects_count
    projects_count=$(jq '.projects | length' "$config_file" 2>/dev/null || echo "0")

    if [ "$projects_count" = "0" ] || [ -z "$projects_count" ]; then
        log_info "No hay proyectos para crear en la configuración"
        return 0
    fi

    # Validar que los grupos existan
    validate_groups_for_projects "$config_file"

    log_info "Procesando ${projects_count} proyecto(s) desde configuración..."

    local created=0
    local skipped=0
    local failed=0
    local i=0

    while [ $i -lt "$projects_count" ]; do
        local current=$((i + 1))
        local project_name
        project_name=$(jq -r ".projects[${i}].name" "$config_file")
        local project_path
        project_path=$(jq -r ".projects[${i}].path // .projects[${i}].name" "$config_file")
        local description
        description=$(jq -r ".projects[${i}].description // \"\"" "$config_file")
        local visibility
        visibility=$(jq -r ".projects[${i}].visibility // \"private\"" "$config_file")
        local group_path
        group_path=$(jq -r ".projects[${i}].group // null" "$config_file")
        
        # Obtener configuración completa del proyecto como JSON
        local project_config
        project_config=$(jq -c ".projects[${i}]" "$config_file")

        log_info "[${current}/${projects_count}] Procesando proyecto '${project_name}'..."

        if create_project "$token" "$project_name" "$project_path" "$description" "$visibility" "$group_path" "$project_config"; then
            created=$((created + 1))
            log_info "[${current}/${projects_count}] ✓ Proyecto '${project_name}' completado"
        else
            local exit_code=$?
            if [ $exit_code -eq 0 ]; then
                skipped=$((skipped + 1))
            else
                failed=$((failed + 1))
                log_error "[${current}/${projects_count}] ✗ Proyecto '${project_name}' falló"
            fi
        fi

        i=$((i + 1))
    done

    log_info "Resumen proyectos: ${created} creados, ${skipped} omitidos, ${failed} fallidos (total: ${projects_count})"
}

# =============================================================================
# Push de un repositorio a GitLab
# =============================================================================
push_single_repository() {
    local token="$1"
    local project_dir="$2"
    local gitlab_path="$3"

    log_info "  Subiendo: ${gitlab_path}"

    # Verificar que el proyecto existe en GitLab
    local project_path_escaped
    project_path_escaped=$(printf '%s' "$gitlab_path" | sed "s/'/\\\\'/g")
    local project_exists
    project_exists=$(${RUNNER_CMD} "
        project = Project.find_by_full_path('${project_path_escaped}')
        puts project ? 'exists' : 'missing'
    " 2>/dev/null | tail -1)

    if [ "$project_exists" != "exists" ]; then
        log_warn "    Proyecto no existe en GitLab: ${gitlab_path}"
        return 1
    fi

    # Construir URL con token
    local remote_url="http://oauth2:${token}@localhost:80/${gitlab_path}.git"

    cd "$project_dir" || { log_error "    No se puede acceder a: ${project_dir}"; return 1; }

    # Configurar git
    git config user.email "init@gitlab.local"
    git config user.name "GitLab Init"
    git config http.sslVerify false

    # Reinicializar repo si .git está vacío (solo marcador)
    if [ ! -f ".git/HEAD" ]; then
        rm -rf .git
        if ! git init -b main >/dev/null 2>&1; then
            log_error "    No se puede inicializar git (¿sistema de archivos read-only?)"
            return 1
        fi
    fi

    # Add y commit si hay cambios
    if ! git add -A 2>&1; then
        log_error "    Error en git add"
        return 1
    fi

    if ! git diff --cached --quiet 2>/dev/null; then
        if ! git commit -m "Initial provisioning" >/dev/null 2>&1; then
            log_error "    Error en git commit"
            return 1
        fi
    fi

    # Verificar que hay commits
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        log_warn "    Repositorio vacío, nada que subir"
        return 0
    fi

    # Configurar remote y push
    git remote remove origin 2>/dev/null || true
    git remote add origin "$remote_url"

    local push_output
    if push_output=$(git push -u origin main 2>&1); then
        log_info "    ✓ Push exitoso"
        return 0
    else
        log_error "    ✗ Push falló: ${push_output}"
        return 1
    fi
}

# =============================================================================
# Push de repositorios desde /repositories
# =============================================================================
push_repositories() {
    local token="$1"
    local repositories_path="/repositories"

    if [ ! -d "$repositories_path" ]; then
        log_info "No hay carpeta /repositories montada, saltando push"
        return 0
    fi

    log_info "Escaneando repositorios en ${repositories_path}..."

    local pushed=0
    local failed=0
    local skipped=0

    # Buscar carpetas .git - el directorio padre es un proyecto
    while IFS= read -r git_dir; do
        local project_dir
        project_dir=$(dirname "$git_dir")

        local gitlab_path="${project_dir#$repositories_path/}"

        if push_single_repository "$token" "$project_dir" "$gitlab_path"; then
            pushed=$((pushed + 1))
        else
            failed=$((failed + 1))
        fi
    done < <(find "$repositories_path" -type d -name ".git" 2>/dev/null)

    if [ $pushed -eq 0 ] && [ $failed -eq 0 ]; then
        log_info "No se encontraron repositorios con .git"
    else
        log_info "Repositorios: ${pushed} subidos, ${failed} fallidos"
    fi
}

# =============================================================================
# Procesar configuración JSON completa
# =============================================================================
process_config_json() {
    local token="$1"
    local config_file="$2"

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    log_info ""
    log_info "=========================================="
    log_info "Procesando configuración desde ${config_file}"
    log_info "=========================================="
    log_info ""

    # ETAPA 1: Crear grupos (sin dependencias)
    log_info "=== ETAPA 1: Creando grupos ==="
    create_groups_from_config "$token" "$config_file"
    log_info "=== ETAPA 1 completada ==="
    log_info ""

    # ETAPA 2: Crear proyectos (dependen de grupos, pero no de usuarios)
    log_info "=== ETAPA 2: Creando proyectos ==="
    create_projects_from_config "$token" "$config_file"
    log_info "=== ETAPA 2 completada ==="
    log_info ""

    # ETAPA 3: Crear usuarios (pueden asignarse después)
    log_info "=== ETAPA 3: Creando usuarios ==="
    create_users_from_config "$token" "$config_file"
    log_info "=== ETAPA 3 completada ==="
    log_info ""

    # ETAPA 4: Asignar usuarios a grupos (después de crear usuarios)
    log_info "=== ETAPA 4: Asignando usuarios a grupos ==="
    assign_users_to_groups_from_config "$token" "$config_file"
    log_info "=== ETAPA 4 completada ==="
    log_info ""

    # ETAPA 5: Push de repositorios
    log_info "=== ETAPA 5: Push de repositorios ==="
    push_repositories "$token"
    log_info "=== ETAPA 5 completada ==="
    log_info ""

    log_info "=========================================="
    log_info "RESUMEN FINAL DE CONFIGURACIÓN"
    log_info "=========================================="

    # Obtener estadísticas finales
    local final_groups
    final_groups=$(${RUNNER_CMD} "puts Group.count" 2>/dev/null | tail -1)
    local final_users
    final_users=$(${RUNNER_CMD} "puts User.count" 2>/dev/null | tail -1)
    local final_projects
    final_projects=$(${RUNNER_CMD} "puts Project.count" 2>/dev/null | tail -1)

    log_info "Total en GitLab:"
    log_info "  - Grupos: ${final_groups}"
    log_info "  - Usuarios: ${final_users}"
    log_info "  - Proyectos: ${final_projects}"
    log_info ""
    log_info "Configuración JSON procesada correctamente"
    log_info "=========================================="
    log_info ""
}

# =============================================================================
# Verificar si ya está inicializado
# =============================================================================
check_already_initialized() {
    # Verificar si el token ya existe Y si hay configuración pendiente
    local token_exists
    token_exists=$(${RUNNER_CMD} "
        user = User.find_by_username('root')
        if user.nil?
          puts 'false'
          exit
        end
        token = user.personal_access_tokens.find_by(name: 'automation-token', revoked: false)
        puts token ? 'true' : 'false'
    " 2>/dev/null)

    if [ "$token_exists" = "true" ]; then
        # Verificar si hay configuración JSON pendiente
        if [ -f "$CONFIG_FILE" ]; then
            # Si hay config.json, verificar si ya se procesó todo
            # Por ahora, siempre procesar config.json si existe
            log_info "Token existe, pero verificando configuración pendiente..."
            return 1
        else
            log_info "GitLab ya está inicializado (token existe, sin config.json)"
            return 0
        fi
    fi

    return 1
}

# =============================================================================
# Main
# =============================================================================
main() {
    log_info "=== Inicialización de GitLab ==="

    # Instalar dependencias necesarias
    install_dependencies

    # Verificar si ya está inicializado
    if check_already_initialized; then
        log_info "Inicialización ya completada, saltando..."
        exit 0
    fi

    # Esperar a GitLab
    wait_for_gitlab || exit 1

    # Obtener contraseña de root
    local root_password
    root_password=$(get_root_password) || exit 1
    log_info "Contraseña de root obtenida"

    # Crear token
    local token
    token=$(create_access_token)

    if [ -z "$token" ]; then
        log_warn "No se pudo crear token de acceso automáticamente"
        log_warn "Puedes crearlo manualmente después de iniciar sesión"
    else
        log_info "Token de acceso creado: ${token}"
        log_warn "Guarda este token de forma segura"

        # Procesar configuración JSON si existe
        local config_file
        config_file=$(read_config "$CONFIG_FILE")
        if [ -n "$config_file" ]; then
            process_config_json "$token" "$config_file"
        fi
    fi

    log_info "=== Inicialización completada ==="
    log_info ""
    log_info "Información de acceso:"
    log_info "  URL: ${GITLAB_URL}"
    log_info "  Usuario: root"
    log_info "  Contraseña: ${root_password}"
    if [ -n "$token" ]; then
        log_info "  Token: ${token}"
    fi
    log_info ""
}

main "$@"
