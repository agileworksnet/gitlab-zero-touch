# Configuración Zero-Touch de GitLab

![GitLab](https://img.shields.io/badge/gitlab-%23181717.svg?style=flat&logo=gitlab&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=flat&logo=kubernetes&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

Una configuración de GitLab Community Edition con **configuración declarativa** e inicialización automatizada. Define toda tu estructura de GitLab—usuarios, grupos y proyectos—en un solo archivo JSON, y despliega una instancia completamente configurada sin intervención manual.

## Características

- **Configuración declarativa**: Define toda tu estructura de GitLab en un solo archivo JSON—usuarios, grupos y proyectos se crean automáticamente
- **Configuración sin intervención**: Configura una vez, despliega en cualquier lugar—no se requiere configuración manual de GitLab
- **Idempotente**: Seguro de ejecutar múltiples veces, solo se inicializa una vez
- **Portable**: Despliega en Docker, Kubernetes o cualquier entorno containerizado
- **Personalizable**: Fácil de configurar mediante variables de entorno y archivos JSON
- **Listo para producción**: Incluye health checks, almacenamiento persistente y optimización de recursos

## ¿Por Qué Esta Configuración?

A diferencia de las instalaciones estándar de GitLab que requieren configuración manual a través de la interfaz web, esta configuración proporciona varias ventajas clave:

- **Infraestructura como Código**: Versiona tu configuración de GitLab junto con tu código. Define usuarios, grupos y proyectos de forma declarativa en JSON
- **Inicialización automatizada**: Sin hacer clic en la interfaz web—toda tu estructura de GitLab se crea automáticamente en el primer arranque
- **Despliegues reproducibles**: Despliega instancias idénticas de GitLab en diferentes entornos (desarrollo, staging, producción) desde el mismo archivo de configuración
- **Ahorro de tiempo**: Configura una instancia completa de GitLab con múltiples usuarios, grupos y proyectos en minutos en lugar de horas
- **Consistencia**: Asegura que todos los entornos tengan la misma estructura, permisos y configuraciones de proyecto
- **Actualizaciones fáciles**: Modifica el archivo JSON y redespliega para actualizar tu configuración de GitLab

## Inicio Rápido

1. Copia el archivo de configuración de ejemplo:
   ```bash
   cp config.json.example config.json
   ```

2. Personaliza `config.json` con tus usuarios, grupos y proyectos

3. Despliega usando tu método preferido (ver [Opciones de Despliegue](#opciones-de-despliegue) a continuación)

4. Espera a que GitLab esté listo (el primer arranque toma 3-5 minutos)

5. Accede a GitLab e inicia sesión con:
   - Usuario: `root`
   - Contraseña: Consulta la sección [Obtener Contraseña de Root](#obtener-contraseña-de-root)

## Opciones de Despliegue

Esta configuración soporta múltiples métodos de despliegue. Elige el que mejor se adapte a tu entorno:

### Docker Compose (Más Simple)

Ideal para desarrollo local, testing o despliegues en servidor único.

**Inicio Rápido:**
```bash
docker compose up -d
```

Accede en `http://localhost:8931` (mapeo de puertos por defecto).

Para instrucciones detalladas, consulta la [sección Docker Compose](#despliegue-con-docker-compose).

### Kubernetes

Ideal para entornos de producción, despliegues en la nube o cuando necesitas características de orquestación.

#### Prerrequisitos

- Cluster de Kubernetes (v1.19 o posterior)
- `kubectl` configurado para acceder a tu cluster
- Registro de imágenes Docker accesible desde tu cluster de Kubernetes
- Recursos suficientes en el cluster:
  - Al menos 4GB de RAM disponible por nodo
  - Almacenamiento para PersistentVolumeClaims (mínimo 80Gi en total)

#### Construcción y Subida de la Imagen

Antes de desplegar, construye y sube la imagen personalizada de GitLab a un registro accesible desde tu cluster:

**Opción 1: Usando ConfigMap (Recomendado)**

Si planeas usar ConfigMap para `config.json`:

```bash
# Construir la imagen (config.json se montará desde ConfigMap)
docker build -t <REGISTRY>/gitlab-custom:latest -f docker/Dockerfile .
docker push <REGISTRY>/gitlab-custom:latest
```

**Opción 2: Configuración Integrada**

Si prefieres integrar `config.json` en la imagen:

```bash
# Asegúrate de que config.json existe
cp config.json.example config.json
# Edita config.json con tus configuraciones

# Construir y subir
docker build -t <REGISTRY>/gitlab-custom:latest -f docker/Dockerfile .
docker push <REGISTRY>/gitlab-custom:latest
```

#### Pasos de Despliegue

1. **Actualizar referencia de imagen** en `k8s/deployment.yaml`:
   ```yaml
   image: tu-registro.com/gitlab-custom:latest
   ```

2. **Crear PersistentVolumeClaims**:
   ```bash
   kubectl apply -f k8s/pvc/
   kubectl get pvc  # Espera a que los PVCs estén vinculados
   ```

3. **Crear ConfigMap** (si usas el enfoque de ConfigMap):
   ```bash
   kubectl apply -f k8s/configmap.yaml
   ```
   O crea el tuyo propio:
   ```bash
   kubectl create configmap gitlab-config-json \
     --from-file=config.json=config.json \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

4. **Desplegar GitLab**:
   ```bash
   kubectl apply -f k8s/deployment.yaml
   kubectl apply -f k8s/service.yaml
   ```

5. **Verificar despliegue**:
   ```bash
   kubectl get pods -l app=gitlab
   kubectl logs -l app=gitlab --tail=50 -f
   ```

#### Acceso a GitLab

**Port Forwarding** (para acceso local rápido):
```bash
kubectl port-forward svc/gitlab 8080:80
# Accede en http://localhost:8080
```

**Ingress** (recomendado para producción):
Crea un recurso Ingress y actualiza `GITLAB_OMNIBUS_CONFIG` en `deployment.yaml` con tu dominio.

#### Requisitos de Recursos

El despliegue solicita:
- **CPU**: 2 núcleos (mínimo), 4 núcleos (límite)
- **Memoria**: 4Gi (mínimo), 8Gi (límite)

Ajusta estos valores en `k8s/deployment.yaml` según la capacidad de tu cluster.

#### Opciones de Configuración

- **Storage Classes**: Si tu cluster requiere una clase de almacenamiento específica, actualiza `storageClassName` en los archivos PVC en `k8s/pvc/`
- **GITLAB_URL**: Configurado a `http://gitlab:80` para comunicación interna (usa service discovery de Kubernetes)
- **ConfigMap vs Integrado**: Elige entre montar `config.json` desde ConfigMap o integrarlo en la imagen

Para instrucciones detalladas, solución de problemas y configuración avanzada, consulta [k8s/README.md](../k8s/README.md).

## Arquitectura

Esta configuración utiliza la imagen oficial GitLab Omnibus, que incluye todos los componentes necesarios en un solo paquete:

- GitLab Rails (aplicación principal)
- PostgreSQL (base de datos)
- Redis (caché y colas)
- Gitaly (servicio de almacenamiento Git)
- GitLab Workhorse (servidor HTTP)
- GitLab Shell (acceso SSH)
- Nginx (proxy inverso)

Todos los componentes están pre-configurados y optimizados para despliegues containerizados.

## Inicialización Automatizada

El sistema de inicialización configura automáticamente GitLab en el primer arranque:

1. Verifica si GitLab ya está inicializado (evita ejecuciones duplicadas)
2. Espera a que GitLab esté disponible y saludable
3. Obtiene la contraseña inicial de root
4. Crea un token de acceso personal para automatización
5. Procesa el archivo `config.json`, creando automáticamente usuarios, grupos y proyectos

La inicialización se ejecuta automáticamente cuando el servicio inicia y solo se ejecuta una vez, haciéndolo seguro para reiniciar o redesplegar.

### Variables de Entorno

Variables de entorno clave para la configuración:

- `GITLAB_URL`: URL interna de GitLab (por defecto: `http://localhost:80`)
- `CONFIG_FILE`: Ruta al archivo de configuración JSON (por defecto: `/opt/gitlab/init-scripts/config.json`)
- `GITLAB_ROOT_PASSWORD`: Contraseña de root (opcional, se obtiene automáticamente si no se especifica)
- `GITLAB_OMNIBUS_CONFIG`: Configuración de GitLab Omnibus (ver sección [Configuración](#configuración))

## Configuración Declarativa mediante JSON

La característica principal de esta configuración es la **configuración declarativa** mediante JSON. En lugar de crear manualmente usuarios, grupos y proyectos a través de la interfaz web de GitLab, defines todo en un solo archivo `config.json`. Este archivo se procesa automáticamente durante la inicialización, creando toda tu estructura de GitLab sin intervención manual.

La configuración soporta usuarios, grupos y proyectos con opciones completas, permitiéndote especificar todo, desde permisos de usuario hasta configuraciones de CI/CD a nivel de proyecto.

### Estructura del Archivo

El archivo `config.json` debe tener la siguiente estructura:

```json
{
  "users": [
    {
      "username": "usuario1",
      "email": "usuario1@example.com",
      "password": "ContraseñaSegura123!",
      "name": "Usuario Uno",
      "is_admin": false,
      "groups": ["grupo1"],
      "skip_confirmation": true
    }
  ],
  "groups": [
    {
      "name": "grupo1",
      "path": "grupo1",
      "description": "Descripción del grupo",
      "visibility": "private"
    }
  ],
  "projects": [
    {
      "name": "proyecto1",
      "path": "proyecto1",
      "description": "Descripción del proyecto",
      "visibility": "private",
      "group": "grupo1",
      "initialize_with_readme": true,
      "default_branch": "main",
      "issues_enabled": true,
      "merge_requests_enabled": true,
      "wiki_enabled": true,
      "snippets_enabled": true,
      "container_registry_enabled": true,
      "lfs_enabled": false,
      "shared_runners_enabled": true,
      "only_allow_merge_if_pipeline_succeeds": false,
      "only_allow_merge_if_all_discussions_are_resueltas": false,
      "allow_merge_on_skipped_pipeline": false,
      "remove_source_branch_after_merge": true,
      "printing_merge_request_link_enabled": true,
      "ci_config_path": ".gitlab-ci.yml"
    }
  ]
}
```

### Campos Disponibles

#### Usuarios
- `username` (requerido): Nombre de usuario
- `email` (requerido): Email del usuario
- `password` (requerido): Contraseña del usuario (debe cumplir la política de contraseñas de GitLab)
- `name` (opcional): Nombre completo (por defecto: username)
- `is_admin` (opcional): Si el usuario es administrador (por defecto: false)
- `groups` (opcional): Array de grupos a los que pertenece
- `skip_confirmation` (opcional): Saltar confirmación de email (por defecto: true)

#### Grupos
- `name` (requerido): Nombre del grupo
- `path` (opcional): Ruta del grupo (por defecto: name)
- `description` (opcional): Descripción del grupo
- `visibility` (opcional): Visibilidad del grupo - `private`, `internal`, o `public` (por defecto: `private`)

#### Proyectos
- `name` (requerido): Nombre del proyecto
- `path` (opcional): Ruta del proyecto (por defecto: name)
- `description` (opcional): Descripción del proyecto
- `visibility` (opcional): Visibilidad - `private`, `internal`, o `public` (por defecto: `private`)
- `group` (opcional): Grupo al que pertenece (se crea automáticamente si no existe)
- `initialize_with_readme` (opcional): Inicializar con README (por defecto: true)
- `default_branch` (opcional): Rama por defecto (por defecto: "main")
- `issues_enabled` (opcional): Habilitar issues (por defecto: true)
- `merge_requests_enabled` (opcional): Habilitar merge requests (por defecto: true)
- `wiki_enabled` (opcional): Habilitar wiki (por defecto: true)
- `snippets_enabled` (opcional): Habilitar snippets (por defecto: true)
- `container_registry_enabled` (opcional): Habilitar registry (por defecto: true)
- `lfs_enabled` (opcional): Habilitar LFS (por defecto: false)
- `shared_runners_enabled` (opcional): Habilitar runners compartidos (por defecto: true)
- `only_allow_merge_if_pipeline_succeeds` (opcional): Solo permitir merge si el pipeline tiene éxito (por defecto: false)
- `only_allow_merge_if_all_discussions_are_resolved` (opcional): Solo permitir merge si todas las discusiones están resueltas (por defecto: false)
- `allow_merge_on_skipped_pipeline` (opcional): Permitir merge en pipeline saltado (por defecto: false)
- `remove_source_branch_after_merge` (opcional): Eliminar rama fuente después de merge (por defecto: true)
- `printing_merge_request_link_enabled` (opcional): Habilitar impresión de link de MR (por defecto: true)
- `ci_config_path` (opcional): Ruta al archivo CI/CD (por defecto: ".gitlab-ci.yml")

### Uso

1. Copia `config.json.example` a `config.json` en la raíz de la carpeta `gitlab/`
2. Personaliza el archivo con tus usuarios, grupos y proyectos
3. El archivo se procesará automáticamente durante la inicialización

**Nota**: El archivo `config.json` está en `.gitignore` para no versionar contraseñas. Usa `config.json.example` como plantilla.

## Configuración

GitLab puede configurarse mediante la variable de entorno `GITLAB_OMNIBUS_CONFIG`. Esta configuración incluye:

- URL externa
- Puerto SSH personalizado
- Optimización de recursos (workers, concurrencia)
- Desactivación de servicios innecesarios
- Desactivación del registro público

Los detalles de configuración varían según el método de despliegue - consulta la documentación específica del despliegue para más detalles.

## Despliegue con Docker Compose

### Prerrequisitos

- Docker y Docker Compose
- Al menos 4GB de RAM disponible
- Espacio en disco suficiente para los datos de GitLab (recomendado: 20GB+)

### Pasos de Despliegue

1. Asegúrate de que `config.json` esté configurado (ver [Configuración JSON](#configuración-mediante-json))

2. Inicia GitLab:
   ```bash
   docker compose up -d
   ```

3. Espera a que GitLab esté listo (el primer arranque toma 3-5 minutos)

4. Accede a GitLab en `http://localhost:8931` (mapeo de puertos por defecto)

### Mapeo de Puertos

Mapeo de puertos por defecto (se pueden cambiar en `docker-compose.yml`):

- `8931:80` - Interfaz web y API
- `8932:443` - HTTPS (si está habilitado)
- `2223:22` - SSH

### Volúmenes

Los datos de GitLab se almacenan en volúmenes Docker:

- `gitlab-config`: Configuración de GitLab
- `gitlab-logs`: Logs del sistema
- `gitlab-data`: Datos de la aplicación (repositorios, base de datos, etc.)

## Obtener Contraseña de Root

### Docker Compose

```bash
docker exec gitlab cat /etc/gitlab/initial_root_password
```

### Kubernetes

```bash
kubectl exec -it deployment/gitlab -- cat /etc/gitlab/initial_root_password
```

## Solución de Problemas

### Contraseña de Root Olvidada

**Docker Compose:**
```bash
docker exec -it gitlab gitlab-rails console
# En consola: User.find_by_username('root').update(password: 'nueva_contraseña')
```

**Kubernetes:**
```bash
kubectl exec -it deployment/gitlab -- gitlab-rails console
# En consola: User.find_by_username('root').update(password: 'nueva_contraseña')
```

### Token de Acceso Expirado

Crea un nuevo token mediante la interfaz web o regenera mediante la consola de Rails:

**Docker Compose:**
```bash
docker exec -it gitlab gitlab-rails console
# En consola:
user = User.find_by_username('root')
token = user.personal_access_tokens.create!(name: 'automation-token', scopes: ['api'], expires_at: 365.days.from_now)
puts token.token
```

**Kubernetes:**
```bash
kubectl exec -it deployment/gitlab -- gitlab-rails console
# Mismos comandos que arriba
```

### Problemas de Memoria

> GitLab requiere al menos 4GB de RAM

1. Reduce los workers en la configuración (ver documentación específica del despliegue)
2. Aumenta los recursos del sistema o reduce el uso de recursos
3. Reinicia el servicio

### La Inicialización No Se Ejecuta

**Docker Compose:**
```bash
docker exec gitlab rm /etc/gitlab/.initialized
docker exec gitlab /opt/gitlab/init-scripts/init-gitlab.sh
```

**Kubernetes:**
```bash
kubectl exec -it deployment/gitlab -- rm /etc/gitlab/.initialized
kubectl exec -it deployment/gitlab -- /opt/gitlab/init-scripts/init-gitlab.sh
```

### El Servicio No Inicia

Revisa los logs según tu método de despliegue:

**Docker Compose:**
```bash
docker compose logs gitlab
```

**Kubernetes:**
```bash
kubectl logs -l app=gitlab
```

## Requisitos

- Runtime de contenedores (Docker o Kubernetes)
- Al menos 4GB de RAM disponible
- Espacio en disco suficiente para los datos de GitLab (recomendado: 20GB+)
- Acceso a red para descargar imágenes (si se usa un registro)

## Licencia

Esta configuración se proporciona tal cual. GitLab Community Edition está licenciado bajo la licencia MIT Expat.

## Referencias

- [Documentación Oficial de GitLab](https://docs.gitlab.com/)
- [Configuración GitLab Omnibus](https://docs.gitlab.com/omnibus/)
- [Imágenes Docker de GitLab](https://docs.gitlab.com/ee/install/docker.html)
