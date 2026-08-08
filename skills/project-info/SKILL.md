---
name: project-info
description: Background, locked decisions and known traps for the Potatoe Task Manager Docker Compose stack (nginx vhost routing, Symfony API scaffold, MariaDB, React Router SPA, seaweedfs, Prometheus, Grafana). Use when working on compose.yml, anything under _docker/, api/, the frontend/ SPA, or the README in this project.
---

# Potatoe Task Manager

Docker Compose dev stack. Services, ports, images and mount rationale are in
`compose.yml` and its comments — read those. Below is only what the files do
not say.

## Current state

- **The stack is a skeleton, not a product.** `api/src` holds `PingController`
  and `HealthController` only; `frontend/app` is a single welcome route. No
  entities, migrations, auth, storage layer or domain code exist — do not assume
  any of it, and do not write code that references it.
- **`_docs/spec.md` is the product spec and is entirely unimplemented.** There are no
  implementation plans on disk — new ones are still to be written.
- A full implementation of the spec was built, rejected and deleted; no branch, remote
  copy or git history survives. What was worth keeping is distilled into
  `_docs/security-model.md` (auth/authorization reference design); everything else is
  gone deliberately, so do not go looking for it.

## Locked decisions

- **No `container_name:`, and `frontend` publishes no host port** — both collided
  with the unrelated `telemetry` stack. Top-level `name: ptm` gives `ptm-<service>-1`
  instead; nginx on `:80` reaches the SPA via service DNS, since all inter-service
  addressing uses compose SERVICE names. Do not re-add either.
- **Every nginx upstream uses the resolver-variable pattern** (`resolver 127.0.0.11
valid=10s;` + `set $x_upstream ...;`), not a static `proxy_pass`/`fastcgi_pass` —
  static targets refuse to start if the backend is down at boot; the variable form
  defers DNS to request time, which is also why nginx carries no `depends_on`. Never
  "simplify" either back.
- **`dev1`–`dev5.ptm.local` are reserved, unclaimed vhost slots** — add a conf.d file
  when claiming one; never reuse a fixed service name for ad-hoc work.
- **seaweedfs S3 auth lives in `_docker/seaweedfs/s3.json`**, mounted read-only into
  the container; `s3.ptm.local` proxies it 1:1 (SigV4 needs `Host` passed through
  unchanged, see `s3.conf`). Any future presigning must be signed against that
  hostname, since the browser — not `api` — consumes the URL.

## Traps

- **Renaming the compose project re-namespaces every volume.** Data looks lost; the
  old volumes still exist under the previous prefix (`docker volume ls`). Migrate or
  accept the reset deliberately — never assume corruption.
- **Never mount tmpfs over a subpath of a bind mount** (e.g.
  `/var/www/api/.phpunit.cache`) — Docker creates the missing directory
  **root-owned on the host**, which then breaks the default uid-1000 workflow. Cost
  real debugging time; isolate caches by compose project, not by tmpfs.
- **`frontend-test`'s container mounts only `frontend/`, so the repo-root
  `.prettierrc` is invisible to it** — its own prettier run won't match repo style.
  Always lint/format via `misc-inspect` (mounts the whole repo); this has bitten
  multiple agents.
- **Benign log noise, do not chase:** MariaDB `io_uring_queue_init() failed with
EPERM` (WSL2), Grafana provisioning warnings, `SQLITE_BUSY` retries at startup.
