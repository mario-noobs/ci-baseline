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

## CI building blocks

The baseline ships two kinds of building blocks. Pick the one whose shape fits the job, compose them in your own workflow file.

### Composite actions (`actions/*`)

Step-level reusables. Use these inside your own job — you keep control of `services:`, `env`, `working-directory`, and step order. Composite actions are how you assemble a CI pipeline without forcing the baseline to know your stack.

| Action | Purpose |
|---|---|
| `actions/setup-python` | Set up Python + pip cache + install base & optional dev requirements |
| `actions/run-pytest` | Run pytest with composed coverage args (`--cov=<paths>`, `--cov-fail-under`, XML report) |
| `actions/setup-node` | Set up Node.js + cache + install for `npm` / `pnpm` / `yarn` |

### Reusable workflows (`.github/workflows/_*.yml`)

Job-level reusables. Use these when the unit of work is a whole job with event-routing or a self-contained stack-agnostic flow.

| Workflow | Purpose |
|---|---|
| `_claude-assistant.yml` | Responds to `@claude` mentions in issues / PR comments |
| `_claude-review.yml` | Auto code review on PRs labelled `claude-review` |
| `_docker-build.yml` | Docker build + push to GHCR |
| `_security-scan.yml` | Trivy filesystem / image scanning |
| `_deploy.yml` | Ansible deploy (checks out caller repo with submodules) |

> **Why no `_ci-<stack>.yml`?** Reusable workflows can't accept `services:` from their caller. Forcing them to bake in a specific service set (Postgres? Redis?) made the baseline grow per stack. Composite actions let each project bring its own services, so the baseline stays small.

## Composition recipes

Copy [`examples/.github/workflows/ci.yml`](examples/.github/workflows/ci.yml) and adapt. Below is the Python backend + Node frontend pattern (matches `ielts-learning-telegram-bot`):

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env: { POSTGRES_USER: app, POSTGRES_PASSWORD: test, POSTGRES_DB: app }
        ports: ["5432:5432"]
        options: --health-cmd "pg_isready -U app -d app" --health-interval 5s --health-retries 10
    env:
      DATABASE_URL: postgresql+asyncpg://app:test@localhost:5432/app
    steps:
      - uses: actions/checkout@v4
      - uses: mario-noobs/ci-baseline/actions/setup-python@main
        with: { python_version: "3.11", dev_requirements_file: requirements-dev.txt }
      - run: ruff check .
      - run: alembic upgrade head
      - uses: mario-noobs/ci-baseline/actions/run-pytest@main
        with:
          coverage_paths: "services bot.utils"
          coverage_min: "15"

  web:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mario-noobs/ci-baseline/actions/setup-node@main
        with: { working_directory: web }
      - working-directory: web
        run: npm run build-storybook -- --quiet

  security:
    uses: mario-noobs/ci-baseline/.github/workflows/_security-scan.yml@main
    with: { scan_type: fs, severity: CRITICAL,HIGH }
```

Project-specific bits — service credentials, env, working-dir, test paths, coverage targets — live in **your workflow file**, not in baseline. To pin to a release, replace `@main` with a tag (e.g. `@v1.2.0`).

## Claude integration

Drop this single file:

```yaml
# .github/workflows/claude.yml
on:
  issue_comment: { types: [created] }
  pull_request_review_comment: { types: [created] }
  issues: { types: [opened, assigned] }
  pull_request: { types: [opened, synchronize, reopened, labeled] }
permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write
jobs:
  assistant: { uses: mario-noobs/ci-baseline/.github/workflows/_claude-assistant.yml@main, secrets: inherit }
  review:    { uses: mario-noobs/ci-baseline/.github/workflows/_claude-review.yml@main,    secrets: inherit }
```

Then:
- Install the official Claude GitHub App: <https://github.com/apps/claude>.
- Add repo secret `ANTHROPIC_API_KEY`.
- (Optional) Create a `claude-review` label for the auto-review flow.
- (Optional) Override model/turns via `vars.CLAUDE_MODEL` (default `claude-sonnet-4-6`), `vars.CLAUDE_MAX_TURNS`, `vars.CLAUDE_REVIEW_MAX_TURNS`.

**Assistant** — mention `@claude` in any issue, PR comment, or new issue body to ask Claude to implement, fix, answer, or create follow-up issues.

**Review** — add the label `claude-review` to a PR; Claude posts inline review comments. Re-runs on every new push while the label is present.

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
