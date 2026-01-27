# GitLab Zero-Touch

![GitLab](https://img.shields.io/badge/gitlab-%23181717.svg?style=flat&logo=gitlab&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=flat&logo=kubernetes&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

A GitLab Community Edition setup with **declarative configuration** and automated initialization. Define your entire GitLab structure—users, groups, and projects—in a single JSON file, and deploy a fully configured instance with zero manual intervention.

## Features

- **Declarative configuration**: Define your entire GitLab structure in a single JSON file—users, groups, and projects are created automatically
- **Zero-touch setup**: Configure once, deploy anywhere—no manual GitLab configuration required
- **Idempotent**: Safe to run multiple times, only initializes once
- **Portable**: Deploy to Docker, Kubernetes, or any containerized environment
- **Customizable**: Easy to configure via environment variables and JSON files
- **Production-ready**: Includes health checks, persistent storage, and resource optimization

## Why This Setup?

Unlike standard GitLab installations that require manual configuration through the web UI, this setup provides several key advantages:

- **Infrastructure as Code**: Version control your GitLab configuration alongside your code. Define users, groups, and projects declaratively in JSON
- **Automated initialization**: No clicking through the UI—your entire GitLab structure is created automatically on first startup
- **Reproducible deployments**: Deploy identical GitLab instances across environments (dev, staging, production) from the same configuration file
- **Time savings**: Set up a complete GitLab instance with multiple users, groups, and projects in minutes instead of hours
- **Consistency**: Ensure all environments have the same structure, permissions, and project settings
- **Easy updates**: Modify the JSON file and redeploy to update your GitLab configuration

## Quick Start

1. Copy the example configuration file:

```bash
cp config.json.example config.json
```

2. Customize `config.json` with your users, groups, and projects

3. Deploy using your preferred method (see [Deployment Options](#deployment-options) below)

4. Wait for GitLab to be ready (first startup takes 3-5 minutes)

5. Access GitLab and login with:
   - Username: `root`
   - Password: See [Getting Root Password](#getting-root-password) section

## Deployment Options

This setup supports multiple deployment methods. Choose the one that best fits your environment:

### Docker Compose (Simplest)

Ideal for local development, testing, or single-server deployments.

**Quick Start:**
```bash
docker compose up -d
```

Access at `http://localhost:8931` (default port mapping).

For detailed instructions, see the [Docker Compose section](#docker-compose-deployment).

### Kubernetes

Ideal for production environments, cloud deployments, or when you need orchestration features.

#### Prerequisites

- Kubernetes cluster (v1.19 or later)
- `kubectl` configured to access your cluster
- Docker image registry accessible by your Kubernetes cluster
- Sufficient cluster resources:
  - At least 4GB RAM available per node
  - Storage for PersistentVolumeClaims (80Gi total minimum)

#### Building and Pushing the Image

Before deploying, build and push the custom GitLab image to a registry accessible by your cluster:

**Option 1: Using ConfigMap (Recommended)**

If you plan to use ConfigMap for `config.json`:

```bash
# Build the image (config.json will be mounted from ConfigMap)
docker build -t <REGISTRY>/gitlab-custom:latest -f docker/Dockerfile .
docker push <REGISTRY>/gitlab-custom:latest
```

**Option 2: Baked-in Configuration**

If you prefer to bake `config.json` into the image:

```bash
# Ensure config.json exists
cp config.json.example config.json
# Edit config.json with your settings

# Build and push
docker build -t <REGISTRY>/gitlab-custom:latest -f docker/Dockerfile .
docker push <REGISTRY>/gitlab-custom:latest
```

#### Deployment Steps

1. **Update image reference** in `k8s/deployment.yaml`:

```yaml
image: your-registry.com/gitlab-custom:latest
```

2. **Create PersistentVolumeClaims**:

```bash
kubectl apply -f k8s/pvc/
kubectl get pvc  # Wait for PVCs to be bound
```

3. **Create ConfigMap** (if using ConfigMap approach):
   ```bash
   kubectl apply -f k8s/configmap.yaml
   ```
   Or create your own:
   ```bash
   kubectl create configmap gitlab-config-json \
     --from-file=config.json=config.json \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

4. **Deploy GitLab**:
   ```bash
   kubectl apply -f k8s/deployment.yaml
   kubectl apply -f k8s/service.yaml
   ```

5. **Verify deployment**:
   ```bash
   kubectl get pods -l app=gitlab
   kubectl logs -l app=gitlab --tail=50 -f
   ```

#### Accessing GitLab

**Port Forwarding** (for quick local access):
```bash
kubectl port-forward svc/gitlab 8080:80
# Access at http://localhost:8080
```

**Ingress** (recommended for production):
Create an Ingress resource and update `GITLAB_OMNIBUS_CONFIG` in `deployment.yaml` with your domain.

#### Resource Requirements

The deployment requests:
- **CPU**: 2 cores (minimum), 4 cores (limit)
- **Memory**: 4Gi (minimum), 8Gi (limit)

Adjust these in `k8s/deployment.yaml` based on your cluster capacity.

#### Configuration Options

- **Storage Classes**: If your cluster requires a specific storage class, update `storageClassName` in the PVC files in `k8s/pvc/`
- **GITLAB_URL**: Set to `http://gitlab:80` for internal communication (uses Kubernetes service discovery)
- **ConfigMap vs Baked-in**: Choose between mounting `config.json` from ConfigMap or baking it into the image

For detailed instructions, troubleshooting, and advanced configuration, see [k8s/README.md](k8s/README.md).

## Architecture

This setup uses the official GitLab Omnibus image, which includes all necessary components in a single package:

- GitLab Rails (main application)
- PostgreSQL (database)
- Redis (cache and queues)
- Gitaly (Git storage service)
- GitLab Workhorse (HTTP server)
- GitLab Shell (SSH access)
- Nginx (reverse proxy)

All components are pre-configured and optimized for containerized deployments.

## Automated Initialization

The initialization system automatically configures GitLab on first startup:

1. Verifies if GitLab is already initialized (prevents duplicate executions)
2. Waits for GitLab to be available and healthy
3. Retrieves the initial root password
4. Creates a personal access token for automation
5. Processes the `config.json` file, automatically creating users, groups, and projects

The initialization runs automatically when the service starts and only executes once, making it safe to restart or redeploy.

### Environment Variables

Key environment variables for configuration:

- `GITLAB_URL`: Internal GitLab URL (default: `http://localhost:80`)
- `CONFIG_FILE`: Path to the JSON configuration file (default: `/opt/gitlab/init-scripts/config.json`)
- `GITLAB_ROOT_PASSWORD`: Root password (optional, automatically retrieved if not specified)
- `GITLAB_OMNIBUS_CONFIG`: GitLab Omnibus configuration (see [Configuration](#configuration) section)

## Declarative JSON Configuration

The core feature of this setup is **declarative configuration** via JSON. Instead of manually creating users, groups, and projects through the GitLab web UI, you define everything in a single `config.json` file. This file is processed automatically during initialization, creating your entire GitLab structure with zero manual intervention.

The configuration supports users, groups, and projects with comprehensive settings, allowing you to specify everything from user permissions to project-level CI/CD configurations.

### File Structure

The `config.json` file must have the following structure:

```json
{
  "users": [
    {
      "username": "user1",
      "email": "user1@example.com",
      "password": "SecurePassword123!",
      "name": "User One",
      "is_admin": false,
      "groups": ["group1"],
      "skip_confirmation": true
    }
  ],
  "groups": [
    {
      "name": "group1",
      "path": "group1",
      "description": "Group description",
      "visibility": "private"
    }
  ],
  "projects": [
    {
      "name": "project1",
      "path": "project1",
      "description": "Project description",
      "visibility": "private",
      "group": "group1",
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
      "only_allow_merge_if_all_discussions_are_resolved": false,
      "allow_merge_on_skipped_pipeline": false,
      "remove_source_branch_after_merge": true,
      "printing_merge_request_link_enabled": true,
      "ci_config_path": ".gitlab-ci.yml"
    }
  ]
}
```

### Available Fields

#### Users
- `username` (required): Username
- `email` (required): User email
- `password` (required): User password (must meet GitLab's password policy)
- `name` (optional): Full name (default: username)
- `is_admin` (optional): Whether user is administrator (default: false)
- `groups` (optional): Array of groups the user belongs to
- `skip_confirmation` (optional): Skip email confirmation (default: true)

#### Groups
- `name` (required): Group name
- `path` (optional): Group path (default: name)
- `description` (optional): Group description
- `visibility` (optional): Group visibility - `private`, `internal`, or `public` (default: `private`)

#### Projects
- `name` (required): Project name
- `path` (optional): Project path (default: name)
- `description` (optional): Project description
- `visibility` (optional): Visibility - `private`, `internal`, or `public` (default: `private`)
- `group` (optional): Group the project belongs to (created automatically if it doesn't exist)
- `initialize_with_readme` (optional): Initialize with README (default: true)
- `default_branch` (optional): Default branch (default: "main")
- `issues_enabled` (optional): Enable issues (default: true)
- `merge_requests_enabled` (optional): Enable merge requests (default: true)
- `wiki_enabled` (optional): Enable wiki (default: true)
- `snippets_enabled` (optional): Enable snippets (default: true)
- `container_registry_enabled` (optional): Enable registry (default: true)
- `lfs_enabled` (optional): Enable LFS (default: false)
- `shared_runners_enabled` (optional): Enable shared runners (default: true)
- `only_allow_merge_if_pipeline_succeeds` (optional): Only allow merge if pipeline succeeds (default: false)
- `only_allow_merge_if_all_discussions_are_resolved` (optional): Only allow merge if all discussions are resolved (default: false)
- `allow_merge_on_skipped_pipeline` (optional): Allow merge on skipped pipeline (default: false)
- `remove_source_branch_after_merge` (optional): Remove source branch after merge (default: true)
- `printing_merge_request_link_enabled` (optional): Enable printing MR link (default: true)
- `ci_config_path` (optional): Path to CI/CD file (default: ".gitlab-ci.yml")

### Usage

1. Copy `config.json.example` to `config.json` in the root of the `gitlab/` folder
2. Customize the file with your users, groups, and projects
3. The file will be processed automatically during initialization

**Note**: The `config.json` file is in `.gitignore` to avoid versioning passwords. Use `config.json.example` as a template.

## Configuration

GitLab can be configured via the `GITLAB_OMNIBUS_CONFIG` environment variable. This configuration includes:

- External URL
- Custom SSH port
- Resource optimization (workers, concurrency)
- Disabling unnecessary services
- Disabling public registration

Configuration details vary by deployment method - see the specific deployment documentation for details.

## Docker Compose Deployment

### Prerequisites

- Docker and Docker Compose
- At least 4GB of available RAM
- Sufficient disk space for GitLab data (recommended: 20GB+)

### Deployment Steps

1. Ensure `config.json` is configured (see [JSON Configuration](#json-configuration))

2. Start GitLab:
   ```bash
   docker compose up -d
   ```

3. Wait for GitLab to be ready (first startup takes 3-5 minutes)

4. Access GitLab at `http://localhost:8931` (default port mapping)

### Port Mappings

Default port mappings (can be changed in `docker-compose.yml`):

- `8931:80` - Web UI and API
- `8932:443` - HTTPS (if enabled)
- `2223:22` - SSH

### Volumes

GitLab data is stored in Docker volumes:

- `gitlab-config`: GitLab configuration
- `gitlab-logs`: System logs
- `gitlab-data`: Application data (repositories, database, etc.)

## Getting Root Password

### Docker Compose

```bash
docker exec gitlab cat /etc/gitlab/initial_root_password
```

### Kubernetes

```bash
kubectl exec -it deployment/gitlab -- cat /etc/gitlab/initial_root_password
```

## Troubleshooting

### Forgotten Root Password

**Docker Compose:**
```bash
docker exec -it gitlab gitlab-rails console
# In console: User.find_by_username('root').update(password: 'new_password')
```

**Kubernetes:**
```bash
kubectl exec -it deployment/gitlab -- gitlab-rails console
# In console: User.find_by_username('root').update(password: 'new_password')
```

### Expired Access Token

Create a new token via the web UI or regenerate via Rails console:

**Docker Compose:**
```bash
docker exec -it gitlab gitlab-rails console
# In console:
user = User.find_by_username('root')
token = user.personal_access_tokens.create!(name: 'automation-token', scopes: ['api'], expires_at: 365.days.from_now)
puts token.token
```

**Kubernetes:**
```bash
kubectl exec -it deployment/gitlab -- gitlab-rails console
# Same commands as above
```

### Memory Issues

> GitLab requires at least 4GB of RAM

1. Reduce workers in configuration (see deployment-specific docs)
2. Increase system resources or reduce resource usage
3. Restart the service

### Initialization Not Running

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

### Service Won't Start

Check logs for your deployment method:

**Docker Compose:**
```bash
docker compose logs gitlab
```

**Kubernetes:**
```bash
kubectl logs -l app=gitlab
```

## Requirements

- Container runtime (Docker or Kubernetes)
- At least 4GB of available RAM
- Sufficient disk space for GitLab data (recommended: 20GB+)
- Network access for image pulls (if using registry)

## License

This setup is provided as-is. GitLab Community Edition is licensed under the MIT Expat license.

## References

- [Official GitLab Documentation](https://docs.gitlab.com/)
- [GitLab Omnibus Configuration](https://docs.gitlab.com/omnibus/)
- [GitLab Docker Images](https://docs.gitlab.com/ee/install/docker.html)
