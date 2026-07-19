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
- **Every nginx upstream — proxy, fastcgi, and the mariadb stream — uses the
  resolver-variable pattern**: `resolver 127.0.0.11 valid=10s;` plus
  `set $x_upstream ...; proxy_pass/fastcgi_pass $x_upstream;`. A static
  `proxy_pass`/`fastcgi_pass` target makes nginx refuse to start if that
  backend is down at boot; the variable form defers the DNS lookup to
  request time, so nginx boots regardless of backend order and returns
  502/refuses the connection until the backend is up. Do not "simplify" any
  vhost or the stream block back to a static target.
- **nginx has no `depends_on`.** The resolver-variable pattern is what makes
  that safe — nginx never needs a backend up at its own startup.
- **Host ports are nginx-only: 80 (all `*.ptm.local` HTTP vhosts) and 3306
  (raw TCP stream to mariadb).** No other service publishes a host port; DB
  clients and browsers alike go through nginx.
- **`dev1.ptm.local` … `dev5.ptm.local` are reserved, unclaimed vhost slots**
  for ad-hoc one-off work — add a conf.d file when claiming one, don't reuse
  the fixed service names (`grafana.ptm.local` etc.) for anything else.
- **seaweedfs S3 auth lives in `_docker/seaweedfs/s3.json`**, mounted
  read-only into the container; `s3.ptm.local` proxies it 1:1 (SigV4 needs
  `Host` passed through unchanged, see `s3.conf`).

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
