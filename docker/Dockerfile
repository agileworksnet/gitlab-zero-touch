FROM gitlab/gitlab-ce:latest

# Instalar jq para procesar JSON
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

# Copiar scripts Ruby al contenedor
COPY docker/scripts/ /opt/gitlab/init-scripts/

# Copiar script de inicialización
COPY docker/init-gitlab.sh /opt/gitlab/init-scripts/

# Copiar archivo de configuración (si existe)
COPY config.json /opt/gitlab/init-scripts/config.json

# Dar permisos de ejecución a los scripts
RUN chmod +x /opt/gitlab/init-scripts/*.rb /opt/gitlab/init-scripts/init-gitlab.sh

# Crear entrypoint wrapper que ejecuta GitLab y luego la inicialización
COPY docker/docker-entrypoint-wrapper.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint-wrapper.sh

# Usar nuestro entrypoint wrapper
ENTRYPOINT ["/usr/local/bin/docker-entrypoint-wrapper.sh"]
