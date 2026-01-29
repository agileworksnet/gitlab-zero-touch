#!/bin/bash
set -e

# Ejecutar el entrypoint original de GitLab en background
# GitLab Omnibus usa /assets/init-container como entrypoint
/assets/init-container "$@" &

# Esperar a que GitLab esté listo
echo "Esperando a que GitLab esté disponible..."
MAX_WAIT=600
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    if /opt/gitlab/bin/gitlab-healthcheck &>/dev/null; then
        echo "GitLab está disponible"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "Error: GitLab no está disponible después de ${MAX_WAIT} segundos"
    exit 1
fi

# Ejecutar script de inicialización solo la primera vez
if [ ! -f /etc/gitlab/.initialized ]; then
    echo "Ejecutando script de inicialización..."

    if [ -z "$GITLAB_URL" ]; then
        echo "Error: GITLAB_URL no está definida"
        exit 1
    fi

    if [ -z "$CONFIG_FILE" ]; then
        echo "Error: CONFIG_FILE no está definida"
        exit 1
    fi

    /opt/gitlab/init-scripts/init-gitlab.sh
    touch /etc/gitlab/.initialized
    echo "Inicialización completada"
fi

# Mantener el proceso principal corriendo
wait
