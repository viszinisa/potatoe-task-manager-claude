---
name: project-info
description: Background, locked decisions and known traps for the Potatoe Task Manager Docker Compose stack (Symfony REST API behind nginx, MariaDB, React Router SPA, Prometheus, Grafana). Use when working on compose.yml, anything under _docker/, api/, the frontend/ SPA, or the README in this project.
---

# Potatoe Task Manager

Docker Compose dev stack. Services, ports, images and mount rationale are in
`compose.yml` and its comments — read those. Below is only what the files do
not say.

## Locked decisions

- **No `container_name:` on any service, ever.** `container_name` is global to
  the Docker daemon, and the unrelated stack at `/home/artis/work/telemetry`
  sets `container_name: mariadb`, `api`, `api-test`, `frontend`. The top-level
  `name: ptm` yields `ptm-<service>-1` instead. Re-adding `container_name`
  reintroduces the collision.
- **`frontend` publishes no host port.** Its 5173 also collided with telemetry
  (which publishes `5173:5173`). nginx on `:80` is the supported way to reach
  the SPA; nginx reaches the Vite dev server by service DNS. Do not re-add a
  5173 host publish.
- **All inter-service addressing uses compose SERVICE names** (nginx upstreams,
  DSNs, prometheus targets). That is what made dropping `container_name` safe —
  service names did not change. Keep it that way.
- **nginx resolves `frontend` at runtime** (`resolver 127.0.0.11`, upstream in a
  variable) so it boots even when `frontend` is down, returning 502. A static
  `proxy_pass http://frontend:5173` makes nginx refuse to start instead. Do not
  "simplify" it back.

## Traps

- **Renaming the compose project re-namespaces every volume.** Data looks lost;
  the old volumes still exist under the previous prefix (`docker volume ls`).
  Migrate or accept the reset deliberately — never assume corruption.
- **`api/migrations/` is empty** (only a `.gitignore`). The entrypoint's
  `doctrine:migrations:migrate --allow-no-migration` therefore succeeds while
  doing nothing, and `task_manager` contains only `doctrine_migration_versions`.
  A missing-table error means no migration was ever written, not a broken run.
- **Prometheus scrapes only itself.** `_docker/prometheus/prometheus.yml` has a
  single `prometheus` job targeting `localhost:9090`; no application target
  exists. README's data-flow line implies otherwise and is stale — no app
  metrics endpoint has been wired.
- **Benign log noise, do not chase:**
    - MariaDB `io_uring_queue_init() failed with EPERM` — WSL2 disables
      io_uring; MariaDB falls back and reports healthy.
    - Grafana `Failed to install plugin ... permission denied` (bundled plugins
      on the data volume) and `Failed to read plugin provisioning files ...
      no such file or directory` (no `provisioning/plugins` dir), plus
      `SQLITE_BUSY` retries at startup.
- **Do not run this stack and telemetry at the same time.** Same Docker daemon,
  overlapping host ports (3306 at minimum, plus telemetry's fixed container
  names).
