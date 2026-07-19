---
name: project-info
description: Background, locked decisions and known traps for the Potatoe Task Manager Docker Compose stack (Symfony REST API behind nginx, MariaDB, LDAP-backed session auth, React Router SPA, Prometheus, Grafana). Use when working on compose.yml, anything under _docker/, api/, the frontend/ SPA, or the README in this project.
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
- **`ldap` is container-to-container only** (no host port); `api` reaches it
  by service name, never through nginx. `ldap.ptm.local` stays a reserved,
  unclaimed vhost — the dev directory (`slapd`) has no web UI to proxy.
- **Auth is session + double-submit CSRF, not tokens.** `security.yaml`'s
  `json_login_ldap` provider resolves users by `sAMAccountName` (not `cn`/DN);
  role hierarchy `ROLE_TS`/`ROLE_DAS` < `ROLE_MODERATOR` < `ROLE_ADMIN` <
  `ROLE_SUPER_ADMIN` comes from LDAP `memberOf` via `App\Security\RoleMapper`
  (`ldap_group_roles` map in `services.yaml`), never stored per-user;
  `effectiveRole` is the highest held, derived not persisted.
  `CsrfProtectionSubscriber` validates `X-XSRF-TOKEN` against the session on
  every mutation.
- **`App\Entity\User` is a local mirror, not the security user.** Keyed by
  `sAMAccountName`, provisioned/refreshed on each login (first real Doctrine
  migration, `api/migrations/Version20260719163431.php`) so later features
  can FK a stable user id. LDAP's `LdapUser` remains the actual security
  principal.
- **`Project::$slug` is immutable** (no setter, set once in the constructor)
  because it seeds task refs; renaming a project must never renumber or
  re-key its existing tasks.
- **`task_type` is seeded via an idempotent migration**
  (`api/migrations/Version20260719171800.php`), `INSERT IGNORE` against the
  unique `name` index, not a fixture/factory — re-running it or seeding
  around manually-added rows never duplicates.
- **The class is `App\Entity\ManagedObject`, table `object`.** PHP forbids a
  class literally named `Object`; `object` is still the table name per spec.
  Objects are only ever created by import (phase 04) — no create endpoint
  exists yet, only edit.
- **Contact fields (`contactName`/`Email`/`Phone1`/`Phone2`) are first-class
  columns on `ManagedObject`, never inside `params`.** They must survive
  re-import (spec: import/sync updates `params`/GPS/type but must not clobber
  contact data a human entered) — phase 04's importer must merge, not
  overwrite, these columns.
- **`StorageInterface` (`App\Storage`) splits transport from presigning.**
  `FlysystemStorage::put/get/delete` run over the internal endpoint
  (`seaweedfs:8333` directly); `temporaryUrl` presigns against a *separate*
  S3 client bound to `s3.ptm.local`, because SigV4 signs the `Host` header
  and the URL is consumed by the browser, not by `api`. The `nginx` service
  carries a `s3.ptm.local` network alias (`compose.yml`) precisely so `api`
  can resolve that same hostname in-network when generating presigned URLs —
  removing the alias breaks presigning even though transport keeps working.
  Phase 08's signed-URL downloads reuse this same port.
- **Image upload allowlist is content-sniffed, not client-declared**
  (`ImageController::ALLOWED_TYPES`: jpeg/png/webp), capped at 10 MiB
  app-side; nginx's `/api/` vhost caps the request body at 12m
  (`_docker/nginx/conf.d/ptm.conf`) so oversize uploads still reach the app
  and get a 422, not a raw nginx 413.

## Traps

- **Renaming the compose project re-namespaces every volume.** Data looks lost;
  the old volumes still exist under the previous prefix (`docker volume ls`).
  Migrate or accept the reset deliberately — never assume corruption.
- **slapd needs its nofile ulimit capped.** The container runtime's default
  `RLIMIT_NOFILE` (~1e9) makes `slapd` size its connection table off it and
  `calloc` ~56GB, aborting on boot. `compose.yml`'s `ldap` service pins
  `ulimits.nofile` to 1024/1024 — do not remove it.
- **The `Symfony\Component\Ldap\Ldap` service needs the literal `ldap` tag**
  in `services.yaml` — `CheckLdapCredentialsListener`'s service locator looks
  it up by that tag, not by autowiring the class.
- **Logout is CSRF-checked even though it's not a state-changing verb by
  convention.** `CsrfProtectionSubscriber::ALWAYS_PROTECTED_PATHS` forces the
  check on `/api/v1/auth/logout` regardless of HTTP method — Symfony's
  `LogoutListener` matches that path for any method, so skipping CSRF on
  "safe" methods there would let a cross-site GET force-logout.
- **Functional/unit tests double LDAP with `App\Tests\Double\FakeLdap`**
  (`api/tests/Double/FakeLdap.php`, password always literal `password`), not
  a live bind to the `ldap` container — keeps `WebTestCase` auth tests
  fast and DAMA-rollback-safe.
- **Prometheus scrapes only itself.** `_docker/prometheus/prometheus.yml` has a
  single `prometheus` job targeting `localhost:9090`; no application target
  exists. README's data-flow line implies otherwise and is stale — no app
  metrics endpoint has been wired.
- **Benign log noise, do not chase:**
    - MariaDB `io_uring_queue_init() failed with EPERM` — WSL2 disables
      io_uring; MariaDB falls back and reports healthy.
    - Grafana `Failed to install plugin ... permission denied` (bundled plugins
      on the data volume) and
      `Failed to read plugin provisioning files ... no such file or directory`
      (no `provisioning/plugins` dir), plus `SQLITE_BUSY` retries at startup.
- **Do not run this stack and telemetry at the same time.** Same Docker daemon,
  overlapping host ports (3306 at minimum, plus telemetry's fixed container
  names).
- **`App\Service\TaskSeqAllocator::allocate()` must run before any other
  auto-increment insert in the same transaction whose ID is still needed via
  `Connection::lastInsertId()`** — its `UPDATE project SET task_seq =
  LAST_INSERT_ID(task_seq + 1) ...` overwrites the connection's session-local
  `LAST_INSERT_ID()` value. It assumes a dedicated per-session DB connection;
  a ProxySQL/MaxScale-style pooler breaks the mechanism. Bypasses the ORM by
  design (`Project` has no `taskSeq` setter) — refresh the entity if the new
  value is needed in-memory.
