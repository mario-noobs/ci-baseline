# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **reusable baseline** consumed by other projects as a git submodule at `ci-scripts/baseline/`. It contains generic Ansible roles, playbooks, reusable GitHub Actions workflows, and a universal deploy wrapper. **It is not deployed standalone** — there is no top-level inventory, no project secrets, no `ansible.cfg` outside `examples/`. Always remember that any change here ships to every consuming repo at the pinned ref.

## Commands

```bash
make setup      # ./scripts/bootstrap.sh — installs ansible, galaxy collections, pre-commit
make lint       # ansible-lint ansible/
make pre-commit # pre-commit run --all-files (trailing-ws, yaml, ansible-lint, actionlint)
```

There is no test suite in this repo. The Ansible playbooks are not runnable from here — they require a project overlay (see `examples/`) that supplies `ansible.cfg`, inventory, and `group_vars`. To exercise an end-to-end deploy, scaffold the overlay from `examples/` into a sibling directory or use a downstream consumer.

## Architecture: the overlay contract

Consumer layout (this is the **only** layout the scripts and playbooks support):

```
your-project/
└── ci-scripts/
    ├── baseline/                    ← this repo as a submodule
    │   ├── ansible/{roles,playbooks,requirements.yml}
    │   ├── .github/workflows/
    │   └── scripts/{deploy.sh,bootstrap.sh}
    ├── ansible/                     ← project-specific overlay
    │   ├── ansible.cfg              ← sets `roles_path = ../baseline/ansible/roles`
    │   ├── group_vars/all/commons.yml
    │   ├── inventories/<env>/<env>.yml
    │   └── files/{init.sql,nginx.conf.j2}
    └── scripts/deploy-<env>.sh      ← thin wrapper → baseline/scripts/deploy.sh
```

Three load-bearing mechanisms tie baseline to overlay — touch them with care:

1. **`roles_path = ../baseline/ansible/roles`** in the overlay's `ansible.cfg`. The overlay invokes baseline playbooks by **relative path** (`../baseline/ansible/playbooks/...`), and the baseline playbooks resolve roles through this setting.
2. **`scripts/deploy.sh`** assumes its parent is `ci-scripts/baseline/`, then `cd`s up and into `../ansible` (the overlay). If you restructure the layout, this script breaks for every consumer.
3. **Project-specific file paths are resolved via `inventory_dir`**, not via Ansible role-search paths. The overlay's `commons.yml` does:
   ```yaml
   _project_ansible_dir: "{{ inventory_dir | dirname | dirname }}"
   app_deploy_nginx_template: "{{ _project_ansible_dir }}/files/nginx.conf.j2"
   app_deploy_init_sql:       "{{ _project_ansible_dir }}/files/init.sql"
   ```
   Roles like `app-deploy` consume these variables — they never hardcode paths into the overlay. When adding a new project-file knob, follow this pattern: declare an empty default in the role's `defaults/main.yml`, gate the task on `var | length > 0`, and document the variable in `README.md`.

## Variable model used by `app-deploy`

The compose template `ansible/roles/app-deploy/templates/docker-compose.yml.j2` renders from two dicts the overlay supplies in `inventories/<env>/group_vars/app_servers.yml`:

- **`app_services`** — project services (image + tag interpolation, env, ports, depends_on, health_check via HTTP). Image refs are emitted as `image:${SERVICE_NAME_TAG:-default}` so per-service tag overrides flow through the `.env` file. `deploy-service.yml` rewrites those lines with `lineinfile` to swap a single service's tag without recreating the whole stack.
- **`infra_services`** — shared infra (mysql, redis, minio, …), gated by `enabled` (typically `"{{ has_mysql }}"` etc. from `commons.yml`). Health-cmd-based, not HTTP-based.

Compose-template subtleties (look here before editing the Jinja — most of the recent commits fix edge cases in it):

- `depends_on` entries are filtered: a dep is dropped if it refers to a disabled infra service or to an external/unknown service. App→app deps use `service_started`; app→infra deps use `service_healthy` when the infra service declares `health_check_cmd`, else `service_started`. Don't add a dep to the rendered output that wasn't through this filter.
- The top-level `volumes:` key is only emitted when at least one infra service declares a *named* volume (paths starting with `.` or `/` are bind mounts and don't count).
- Network is `bridge` by default; setting `network_external: true` joins an existing external docker network of name `{{ network_name }}` instead of creating one.
- The image reference uses literal `${...}` brace syntax that must be escaped in Jinja (`{{ '{' }}` / `{{ '}' }}`) — see commit `b0e1237`.

## CI building blocks — composite actions vs reusable workflows

Baseline ships **two** kinds of GitHub Actions building blocks, picked by shape, not by language:

- **Composite actions** under `actions/<name>/action.yml` — step-level reusables. Used inside the consumer's own job (`- uses: mario-noobs/ci-baseline/actions/<name>@<ref>`). Consumer keeps full control of `services:`, `env:`, `working-directory`, and step ordering. **This is where stack-flavoured logic lives** (`setup-python`, `run-pytest`, `setup-node`).
- **Reusable workflows** under `.github/workflows/_*.yml` — job-level reusables, `workflow_call` only (`uses: …/_*.yml@<ref>` at the job level). **Reserved for two cases:** (a) event-routing units that need to be a full workflow (`_claude-assistant.yml`, `_claude-review.yml`) and (b) self-contained, stack-agnostic jobs that don't need consumer-side `services:` (`_security-scan.yml`, `_docker-build.yml`, `_deploy.yml`).

**The bright line:** if a job needs `services:` or stack-specific environment, it belongs in the consumer's workflow file composed from composite actions — NOT in a reusable workflow. The original `_ci-{java,python,node}.yml` workflows hit this wall (services can't be conditionalized from `workflow_call` inputs, and callers can't inject them) and were deleted on `2026-05-14`. Don't recreate that shape.

When editing the surviving workflows:

- **Claude workflows** (`_claude-assistant.yml`, `_claude-review.yml`) use `anthropics/claude-code-action@v1` and assume the **official Anthropic GitHub App** is installed on the consumer repo (not a custom branded app). They need only `ANTHROPIC_API_KEY`. Permissions declared in the reusable workflow are **capped** by the caller workflow's `permissions:` block — that's why `examples/.github/workflows/claude.yml` declares the full permission set at the caller level. Don't remove those caller-level permissions.
- `_claude-review.yml` is **label-gated** on `claude-review`. The `if:` covers both the `labeled` event and `opened`/`synchronize`/`reopened` where the label is already present. The label name is hardcoded — don't add a variable for it without an actual ask.
- `_deploy.yml` checks out the **caller's** repo with `submodules: recursive` and then `cd`s into `${{ inputs.ci_scripts_path }}/ansible` (default `ci-scripts/ansible`). It calls baseline playbooks by relative path — keep that path stable.
- `_deploy.yml` optionally joins Tailscale (when `tailscale_tags` is non-empty) and optionally uses an Ansible vault password (when the secret is set). Both code paths are conditional — preserve the "optional secret" pattern when adding new auth.

When editing composite actions:

- Each action.yml uses `runs.using: composite` and shell steps must declare `shell: bash` explicitly (composite-action requirement).
- Inputs that map to shell-expanded commands (e.g. `run-pytest`'s `coverage_paths` arg-builder) are passed via `env:` and consumed as `${VAR}` in the script body, not interpolated directly with `${{ … }}` into the script — keeps quoting predictable across shells.
- Don't ship a composite that wraps a single one-line shell call (e.g. `ruff check .`, `alembic upgrade head`). Consumers write those as `- run:` steps directly. Only ship a composite when it bundles meaningful setup or non-trivial argument composition.

## Conventions worth knowing

- **Image refs in compose** always go through the `${SERVICE_TAG:-default}` form so deploy-service.yml can hot-swap a single service without a full re-render.
- **Registry login is best-effort** (`registry-login` role): when `registry_username`/`registry_password` are empty, it logs a debug message and continues — public images still pull. Keep this behavior; consumers rely on it for OSS image pulls without secrets.
- **All baseline-shipped variables have empty/safe defaults** in `defaults/main.yml`. The overlay always opts in. Never make a baseline role require a project-specific path to render.
- **Indentation is 2 spaces** (see `.editorconfig`), tab in `Makefile` only. YAML files must lint clean under `ansible-lint v24.2.0` and `actionlint v1.6.27` (pinned in `.pre-commit-config.yaml`).
