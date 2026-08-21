---
name: lint-code
description: Use after writing or editing code in this project, or whenever asked to lint, auto-format or fix code style — php-inspect (PHP-CS-Fixer, Symfony ruleset) for PHP, misc-inspect (prettier) for YAML/JSON/Markdown and other prettier-supported files, shellcheck for shell scripts.
---

# Linting code in this repo

All linting runs through three Docker Compose services under the `tools`
profile (all network-less, running as uid 1000 so fixed files stay owned by
the repo user). Pick the tool by file type:

| File type | Tool | Service |
| --- | --- | --- |
| PHP (`api/`) | PHP-CS-Fixer (`@Symfony`) | `php-inspect` |
| YAML, JSON, Markdown, and anything prettier supports | prettier | `misc-inspect` |
| Shell scripts (`.sh`) | shellcheck | `shellcheck` |

There is no overlap: prettier has no PHP plugin installed and skips `.php`
files; PHP-CS-Fixer only sees `api/`; neither reads `.sh`.

## PHP — php-inspect

Config lives at `api/.php-cs-fixer.dist.php` and uses the `@Symfony` rule set
(with `yoda_style` and `increment_style` disabled — Claude's natural style,
per the CLAUDE.md rule to amend rules that constantly conflict), 4-space
indent, cache in the container's `/tmp`, excluding `var/` + `vendor/`.

```bash
# check (dry-run, non-zero exit on violations)
docker compose --profile tools run --rm php-inspect check --config api/.php-cs-fixer.dist.php

# fix in place
docker compose --profile tools run --rm php-inspect fix --config api/.php-cs-fixer.dist.php
```

Add `--diff` to `check` to see what would change.

PHP sources are bind-mounted into the containers (`./api` at `/var/www/api`),
so a fix applies without an image rebuild — just re-verify
(`curl --cacert _docker/nginx/ssl/rootCA.pem https://ptm.local/api/v1/health`, the PHPUnit suite). Rebuild only when a
Dockerfile or `composer.json` changed.

## Everything else — misc-inspect

prettier (pinned in `_docker/misc-inspect/Dockerfile`), config `.prettierrc`
at repo root (`tabWidth: 4`, `printWidth: 120` — user has a wide screen),
excludes in `.prettierignore` (vendor, var, node_modules, build output). The
container mounts the whole repo at `/code`; the image entrypoint is
`prettier`, so pass prettier args directly:

```bash
docker compose --profile tools run --rm misc-inspect --check .   # lint
docker compose --profile tools run --rm misc-inspect --write .   # fix in place
```

Paths instead of `.` work too (e.g. `--check compose.yml _docker/`).

After `--write` touches mounted service configs, restart the affected
services and check health: `_docker/prometheus/*` or
`_docker/grafana/dashboards/*` → `docker compose restart prometheus grafana`;
`compose.yml` → `docker compose config -q` to validate.

**Markdown gotcha:** prettier's markdown printer is not idempotent — `--check` never goes green after `--write` — when
an inline code span wraps across lines inside a list item. Fix: keep inline code spans on one line, indent list-item
continuation paragraphs 2 spaces, re-run `--write` once.

## Shell — shellcheck

Official `koalaman/shellcheck` image; its entrypoint is the `shellcheck`
binary itself, so pass file paths directly. The container mounts the whole
repo read-only at `/code`, so use repo-relative paths:

```bash
docker compose --profile tools run --rm shellcheck _docker/api/docker-entrypoint.sh
docker compose --profile tools run --rm shellcheck _docker/nginx/generate-certs.sh
```

No `--write` equivalent — shellcheck only reports; fix findings by hand. A
false positive gets a targeted `# shellcheck disable=<code>` comment above
the flagged line with a reason, never a blanket disable for the file. Do not
apply a suggested rewrite that changes behaviour (e.g. SC2209 on an inline
`VAR=val cmd` env-prefix idiom, which is correct shell, not a mistaken
assignment).

## Version pins

- PHP-CS-Fixer: image tag on the `php-inspect` service in `compose.yml`
  (`ghcr.io/php-cs-fixer/php-cs-fixer:<version>-php8.5`).
- prettier + node: `_docker/misc-inspect/Dockerfile`.
- shellcheck: image tag on the `shellcheck` service in `compose.yml`
  (`koalaman/shellcheck:<version>`).

Per CLAUDE.md, keep all three on the newest available pinned versions.
