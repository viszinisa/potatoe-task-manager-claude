---
name: basic-information-about-project
description: Background, locked decisions and known traps for the Potatoe Task Manager Docker Compose stack (Symfony REST API behind nginx, MariaDB, React Router SPA, Prometheus, Grafana). Use when working on compose.yml, anything under _docker/, api/, the frontend/ SPA, or the README in this project.
---

# Potatoe Task Manager

New project. **No architectural decisions are locked in yet, and no traps are
known yet** — do not infer either from the current file layout.

Current facts, and nothing beyond them:

- Services: `mariadb`, `api`, `nginx`, `frontend`, `prometheus`, `grafana`
  (always on); `api-test`, `frontend-test`, `playwright` (profile `test`);
  `php-inspect`, `misc-inspect` (profile `tools`).
- The API has exactly two endpoints: `GET /api/v1/ping` → `pong`, and
  `GET /api/v1/health`.
- The frontend is a bare welcome page.

Record decisions and traps here as they are made — CLAUDE.md and README.md
both point at this skill as the place they live.
