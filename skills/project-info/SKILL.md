---
name: project-info
description: Background, locked decisions and known traps for the Potatoe Task Manager Docker Compose stack (Symfony REST API behind nginx, MariaDB, LDAP-backed session auth, React Router SPA, Prometheus, Grafana). Use when working on compose.yml, anything under _docker/, api/, the frontend/ SPA, or the README in this project.
---

# Potatoe Task Manager

Docker Compose dev stack. Services, ports, images and mount rationale are in
`compose.yml` and its comments — read those. Below is only what the files do
not say.

## Locked decisions

- **No `container_name:`, and `frontend` publishes no host port** — both
  collided with the unrelated `/home/artis/work/telemetry` stack
  (`container_name: mariadb/api/api-test/frontend`, `5173:5173`). Top-level
  `name: ptm` gives `ptm-<service>-1` instead; nginx on `:80` is the
  supported way to reach the SPA (service DNS to Vite). Do not re-add either.
- **All inter-service addressing uses compose SERVICE names** (nginx upstreams,
  DSNs, prometheus targets). That is what made dropping `container_name` safe —
  service names did not change. Keep it that way.
- **Every nginx upstream uses the resolver-variable pattern**
  (`resolver 127.0.0.11 valid=10s;` + `set $x_upstream ...;`), not a static
  `proxy_pass`/`fastcgi_pass` — static targets make nginx refuse to start
  if the backend is down at boot; the variable form defers DNS to request
  time so nginx boots regardless of backend order. Never "simplify" back.
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
- **Auth is session + double-submit CSRF, not tokens.** `json_login_ldap`
  resolves users by `sAMAccountName` (not `cn`/DN); role hierarchy
  `ROLE_TS`/`ROLE_DAS` < `MODERATOR` < `ADMIN` < `SUPER_ADMIN` comes from
  LDAP `memberOf` via `RoleMapper`, never stored per-user — `effectiveRole`
  is the highest held, derived not persisted. `CsrfProtectionSubscriber`
  checks `X-XSRF-TOKEN` against the session on every mutation.
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
  re-import — the phase 04 importer's external_id upsert merges, never
  overwrites, these columns. Never make the import path write to them.
- **`App\Service\CoordinateConverter`-style LKS-92→WGS-84 conversion is a
  self-contained port of the laacz gist formulas — never add `proj4php` or
  another projection library.** It's a handful of closed-form equations, not
  worth a dependency.
- **`StorageInterface` (`App\Storage`) splits transport from presigning.**
  `FlysystemStorage` talks `seaweedfs:8333` directly; `temporaryUrl` presigns
  against a *separate* client bound to `s3.ptm.local` (SigV4 signs `Host`,
  and the browser — not `api` — consumes the URL). `nginx`'s `s3.ptm.local`
  network alias exists solely so `api` can resolve that hostname in-network;
  removing it breaks presigning even though transport keeps working.
- **Image upload allowlist is content-sniffed, not client-declared**
  (`ImageController::ALLOWED_TYPES`: jpeg/png/webp), capped at 10 MiB
  app-side; nginx's `/api/` vhost caps the request body at 12m
  (`_docker/nginx/conf.d/ptm.conf`) so oversize uploads still reach the app
  and get a 422, not a raw nginx 413.
- **`ObjectListQuery` (`api/src/Query/ObjectListQuery.php`) never
  interpolates user input into SQL.** Filterable fields come from a fixed
  allowlist map; `params.*` JSON keys are regex-validated before being
  placed in a `JSON_EXTRACT` path, and every value is bound as a DBAL
  parameter. Extending the field set must keep both — pattern-validate the
  key, bind the value.
- **Tasks are immutable by design** — `Task`/`TaskAssignment`/`TaskObject`
  fields are `readonly`, no PATCH/PUT/DELETE route exists or should
  (405 if attempted). Modeled on signed work orders: correcting a mistake
  means cancel-and-recreate, never editing history.
- **`TaskTransitioner` is the sole caller of `Task::markState`; `ObjectTransitioner`
  is the sole mutator of `task_object.state`** — same conditional-UPDATE mutex
  convention (`affected === 0` => 409, not a retry); the latter also opens/closes
  the matching `Worklog` row in the same DB transaction.
- **`Worklog.open_key` is a virtual generated column, not a partial index** —
  MariaDB has no `WHERE`-clause partial index support, so the single-open-row
  invariant is a plain unique index over a column computed as `task_id-object_id`
  while open, `NULL` once finished (NULLs distinct in MariaDB). Never reach
  for a partial index here.
- **`GET /worker/objects` tabs derive from state + `plannedInspectionAt`, not
  a stored column** — finished/cancelled → completed, active/paused → active,
  else by planned date vs. today (UTC): null → not_planned, future → planned,
  today-or-past-due → planned_today.
- **Task assignment usernames validate against the local `User` mirror,
  not LDAP** — an unknown username 422s ("no user-search endpoint yet",
  phase 09); the assignee must already have logged in once (login-provisioned mirror).

## Traps

- **Renaming the compose project re-namespaces every volume.** Data looks lost;
  the old volumes still exist under the previous prefix (`docker volume ls`).
  Migrate or accept the reset deliberately — never assume corruption.
- **slapd needs its nofile ulimit capped** — the default `RLIMIT_NOFILE`
  (~1e9) makes it `calloc` ~56GB sizing its connection table and abort on
  boot; `compose.yml` pins `ulimits.nofile` to 1024/1024 — do not remove it.
- **The `Symfony\Component\Ldap\Ldap` service needs the literal `ldap` tag**
  in `services.yaml` — `CheckLdapCredentialsListener`'s service locator looks
  it up by that tag, not by autowiring the class.
- **Logout is CSRF-checked despite not being state-changing by convention**
  — `ALWAYS_PROTECTED_PATHS` forces the check regardless of HTTP method,
  since `LogoutListener` matches any method (skipping "safe" ones would
  let a cross-site GET force-logout).
- **Functional/unit tests double LDAP with `App\Tests\Double\FakeLdap`**
  (password always literal `password`), not a live bind to `ldap` — keeps
  `WebTestCase` auth tests fast and DAMA-rollback-safe.
- **Prometheus scrapes only itself.** `_docker/prometheus/prometheus.yml` has a
  single `prometheus` job targeting `localhost:9090`; no app metrics endpoint
  is wired yet.
- **Benign log noise, do not chase:** MariaDB `io_uring_queue_init() failed
  with EPERM` (WSL2 fallback), Grafana plugin-install/provisioning warnings,
  and `SQLITE_BUSY` retries at startup.
- **`messenger-worker`'s scheduler rebuilds its schedule only at container
  boot** (hourly recycle) — creating or editing a `DataSource`'s import
  schedule has no effect until the worker restarts; it does not poll the DB.
- **`HttpFetchGuard` denies private/loopback IP ranges by default** (SSRF
  protection on import fetches, http/https only, no redirects, 30s/20MB caps).
  Dev `.env` sets `IMPORT_ALLOW_PRIVATE_NETWORKS=1` so imports can reach
  sibling containers — never set it outside dev.
- **`messenger_messages` needs no `schema_filter` entry** —
  `DoctrineTransport::configureSchema()` already hooks into the same
  schema-diff pass `doctrine:migrations:diff` uses.
- **`App\Service\TaskSeqAllocator::allocate()` must run before any other
  auto-increment insert in the same transaction whose ID is still needed via
  `Connection::lastInsertId()`** — its `UPDATE project SET task_seq =
  LAST_INSERT_ID(task_seq + 1) ...` overwrites the connection's session-local
  `LAST_INSERT_ID()` value. It assumes a dedicated per-session DB connection;
  a ProxySQL/MaxScale-style pooler breaks the mechanism. Bypasses the ORM by
  design (`Project` has no `taskSeq` setter) — refresh the entity if the new
  value is needed in-memory.
