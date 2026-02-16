# ci-baseline

Reusable CI/CD workflows and Ansible deployment baseline. Add as a **git submodule** to any project and overlay with project-specific configuration.

## Architecture

```
your-project/
├── ci-scripts/
│   ├── baseline/                  ← git submodule → this repo
│   │   ├── ansible/roles/        ← Generic roles (common, docker, security, etc.)
│   │   ├── ansible/playbooks/    ← Generic playbooks (deploy-all, rollback, etc.)
│   │   ├── .github/workflows/    ← Reusable GH Actions (_ci-java, _docker-build, etc.)
│   │   └── scripts/deploy.sh     ← Universal deploy wrapper
│   │
│   ├── ansible/
│   │   ├── ansible.cfg           ← roles_path = ../baseline/ansible/roles
│   │   ├── group_vars/all/commons.yml  ← Project identity + file path overrides
│   │   ├── inventories/dev/...   ← Project-specific hosts, services, secrets
│   │   └── files/                ← Project-specific files (init.sql, nginx.conf.j2)
│   │
│   └── scripts/deploy-dev.sh     ← Calls baseline/scripts/deploy.sh
```

**Key mechanism**: `ansible.cfg` sets `roles_path = ../baseline/ansible/roles`. Deploy scripts call baseline playbooks via relative path. Project-specific files (init.sql, nginx.conf.j2) are referenced via variables in `commons.yml`.

## Quick Start

### 1. Add submodule to your project

```bash
cd your-project
mkdir -p ci-scripts
cd ci-scripts
git submodule add https://github.com/mario-noobs/ci-baseline.git baseline
```

### 2. Copy the scaffold

```bash
cp -r baseline/examples/ansible ./ansible
cp -r baseline/examples/scripts ./scripts
cp baseline/examples/Makefile ./Makefile
```

### 3. Customize

Edit these files for your project:

- `ansible/group_vars/all/commons.yml` — project name, registry, feature flags
- `ansible/inventories/dev/group_vars/app_servers.yml` — services, images, ports
- `ansible/inventories/dev/group_vars/vault.yml` — secrets (encrypt with `ansible-vault`)
- `ansible/files/init.sql` — database initialization
- `ansible/files/nginx.conf.j2` — nginx configuration

### 4. Deploy

```bash
./scripts/deploy-dev.sh
```

## Reusable Workflows

Service repos call these via `workflow_call`:

| Workflow | Purpose |
|----------|---------|
| `_ci-java.yml` | Java build, test, JaCoCo, SonarCloud |
| `_ci-python.yml` | Python lint (ruff/flake8), test |
| `_ci-node.yml` | Node build, lint, test |
| `_docker-build.yml` | Docker build + push to GHCR |
| `_security-scan.yml` | Trivy + OWASP scanning |
| `_deploy.yml` | Ansible deploy to target env (checks out caller repo with submodules) |

### Usage in service repo

```yaml
jobs:
  ci:
    uses: mario-noobs/ci-baseline/.github/workflows/_ci-java.yml@main
    with:
      sonar_project_key: my-org_my-service
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}

  deploy:
    needs: [ci]
    uses: mario-noobs/ci-baseline/.github/workflows/_deploy.yml@main
    with:
      environment: dev
      image_tag: sha-abc1234
      ci_scripts_path: ci-scripts    # path to overlay in your repo
    secrets:
      SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
      ANSIBLE_VAULT_PASSWORD: ${{ secrets.ANSIBLE_VAULT_PASSWORD }}
```

## Ansible Roles

| Role | Purpose |
|------|---------|
| `common` | Base OS setup, swap, sysctl, deploy user |
| `security` | UFW, fail2ban, SSH hardening |
| `docker` | Docker CE + compose plugin |
| `registry-login` | GHCR/ECR/DockerHub auth |
| `app-deploy` | Render compose, pull, up, healthcheck |
| `certbot` | Let's Encrypt SSL |
| `db-backup` | MySQL backup + cron |
| `monitoring` | Log rotation, health checks |

## Playbooks

| Playbook | Purpose |
|----------|---------|
| `setup/site.yml` | Full server bootstrap (all roles) |
| `deploy/deploy-all.yml` | Deploy full stack |
| `deploy/deploy-service.yml` | Deploy single service |
| `deploy/rollback.yml` | Rollback to previous tag |
| `maintenance/dump.yml` | Database dump and fetch |
| `maintenance/cleanup-images.yml` | Docker image prune |
| `test.yml` | Connectivity and health tests |

## Project-Specific Files

The `app-deploy` role supports variable-based paths for project-specific files:

| Variable | Purpose | Set in |
|----------|---------|--------|
| `app_deploy_nginx_template` | Path to nginx.conf.j2 template | `commons.yml` |
| `app_deploy_init_sql` | Path to init.sql file | `commons.yml` |

These are resolved via `inventory_dir`:
```yaml
_project_ansible_dir: "{{ inventory_dir | dirname | dirname }}"
app_deploy_nginx_template: "{{ _project_ansible_dir }}/files/nginx.conf.j2"
app_deploy_init_sql: "{{ _project_ansible_dir }}/files/init.sql"
```

## Development

```bash
make setup      # Install Ansible + pre-commit
make lint       # Run ansible-lint
make pre-commit # Run all pre-commit hooks
```
