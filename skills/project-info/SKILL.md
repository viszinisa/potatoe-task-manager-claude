---
name: project-info
description: Background, locked decisions and known traps for the Potatoe Task Manager Docker Compose stack (Symfony REST API behind nginx, MariaDB, LDAP-backed session auth, React Router SPA, Prometheus, Grafana). Use when working on compose.yml, anything under _docker/, api/, the frontend/ SPA, or the README in this project.
---

# Potatoe Task Manager

Docker Compose dev stack. Services, ports, images and mount rationale are in
`compose.yml` and its comments — read those. Below is only what the files do
not say.

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
- **`dev1.ptm.local` … `dev5.ptm.local` are reserved, unclaimed vhost slots** — add a
  conf.d file when claiming one; never reuse a fixed service name for ad-hoc work.
- **seaweedfs S3 auth lives in `_docker/seaweedfs/s3.json`**, mounted read-only into
  the container; `s3.ptm.local` proxies it 1:1 (SigV4 needs `Host` passed through
  unchanged, see `s3.conf`).
- **`ldap` is container-to-container only** (no host port), reached by service name,
  never through nginx; `ldap.ptm.local` stays reserved, unclaimed — `slapd` has no
  web UI to proxy.
- **Auth is session + double-submit CSRF, not tokens.** `json_login_ldap` resolves
  users by `sAMAccountName` (not `cn`/DN); role hierarchy `ROLE_TS`/`ROLE_DAS` <
  `MODERATOR` < `ADMIN` < `SUPER_ADMIN` comes from LDAP `memberOf` via `RoleMapper`,
  never stored per-user — `effectiveRole` is the highest held, derived not
  persisted. `CsrfProtectionSubscriber` checks `X-XSRF-TOKEN` against the session on
  every mutation.
- **Phase 09 authorization is a full voter matrix, not coarse guards** —
  `access_control` in `security.yaml` stays auth-only (authenticated vs anonymous),
  never grows a role/permission line; every resource decision runs through a Voter.
  Per-task caps (`TaskAssignmentRepository::hasRole`) never elevate system-role caps
  (pinned by tests); image/object-tag mutations stay any-authenticated by documented
  interpretation — spec-silent, product-owner ruling pending.
- **`App\Entity\User` is a local mirror, not the security user.** Keyed by
  `sAMAccountName`, provisioned/refreshed on each login; LDAP's `LdapUser` remains
  the actual security principal.
- **`Project::$slug` is immutable** (no setter, set once in the constructor) — it
  seeds task refs, so renaming a project must never renumber or re-key its tasks.
- **`task_type` is seeded via an idempotent migration**, `INSERT IGNORE` against the
  unique `name` index, not a fixture/factory — re-running it or seeding around
  manually-added rows never duplicates.
- **The class is `App\Entity\ManagedObject`, table `object`.** PHP forbids a class
  literally named `Object`; `object` is still the table name per spec. Objects are
  only ever created by import (phase 04) — no create endpoint exists yet, only edit.
- **Contact fields (`contactName`/`Email`/`Phone1`/`Phone2`) are first-class columns
  on `ManagedObject`, never inside `params`.** They must survive re-import — the
  phase 04 importer's external_id upsert merges, never overwrites, these columns.
  Never make the import path write to them.
- **`api/src/Import/Lks92ToWgs84.php` is a self-contained port of the laacz
  gist's LKS-92→WGS-84 formulas** — a handful of closed-form equations, never
  worth adding `proj4php` or another projection library.
- **`StorageInterface` (`App\Storage`) splits transport from presigning.**
  `FlysystemStorage` talks `seaweedfs:8333` directly; `temporaryUrl` presigns against
  a _separate_ client bound to `s3.ptm.local` (SigV4 signs `Host`; the browser, not
  `api`, consumes the URL). nginx's `s3.ptm.local` alias exists only so `api` can
  resolve that hostname — removing it breaks presigning.
- **Image upload allowlist is content-sniffed, not client-declared**
  (`ImageController::ALLOWED_TYPES`: jpeg/png/webp), capped at 10 MiB app-side; nginx
  caps the request body at 12m (`_docker/nginx/conf.d/ptm.conf`) so oversize uploads
  get a 422, not a raw nginx 413.
- **`ObjectListQuery` (`api/src/Query/ObjectListQuery.php`) never interpolates user
  input into SQL.** Filterable fields come from a fixed allowlist map; `params.*`
  JSON keys are regex-validated before being placed in a `JSON_EXTRACT` path, and
  every value is bound as a DBAL parameter. Extending the field set must keep both —
  pattern-validate the key, bind the value.
- **Tasks are immutable by design** — `Task`/`TaskAssignment`/`TaskObject` fields
  are `readonly`, no PATCH/PUT/DELETE route exists or should (405 if attempted).
  Modeled on signed work orders: correcting a mistake means cancel-and-recreate,
  never editing history.
- **`TaskTransitioner` is the sole caller of `Task::markState`; `ObjectTransitioner`
  is the sole mutator of `task_object.state`** — same conditional-UPDATE mutex
  convention (`affected === 0` => 409, not a retry); the latter also opens/closes
  the matching `Worklog` row in the same DB transaction.
- **`Worklog.open_key` is a virtual generated column, not a partial index** —
  MariaDB has no `WHERE`-clause partial index support, so the single-open-row
  invariant is a plain unique index over a column computed as `task_id-object_id`
  while open, `NULL` once finished (NULLs distinct in MariaDB). Never reach for a
  partial index here.
- **`GET /worker/objects` tabs derive from state + `plannedInspectionAt`, not a
  stored column** — finished/cancelled → completed, active/paused → active, else by
  planned date vs. today (UTC): null → not_planned, future → planned,
  today-or-past-due → planned_today.
- **Task assignment usernames validate against the local `User` mirror, not LDAP** —
  assignee must have logged in once. Phase 09's `GET /users?forRole` (MODERATOR+,
  sort-only) feeds the wizard picker that replaced the old free-text field.
- **`TaskDocTemplate` has no update path, ever** — delete + re-upload only. Modeled
  on signed documents: a template must never change out from under a doc already
  generated from it. Never add a PUT/PATCH route for it.
- **The `${...}` placeholder contract has one source of truth** —
  `App\Service\Document\TaskDocumentGenerator`'s docblock. Add a token there (and in
  the upload-form help text), never duplicate the list elsewhere.
- **`TaskDocumentGenerator` builds the objects table with PHPWord `setComplexBlock`,
  not `cloneRow`** — `cloneRow` can't produce a configurable/ordered column set
  (`TaskDocTemplate.columns` JSON).

## Traps

- **Renaming the compose project re-namespaces every volume.** Data looks lost; the
  old volumes still exist under the previous prefix (`docker volume ls`). Migrate or
  accept the reset deliberately — never assume corruption.
- **slapd needs its nofile ulimit capped** — the default `RLIMIT_NOFILE` (~1e9)
  makes it `calloc` ~56GB sizing its connection table and abort on boot;
  `compose.yml` pins `ulimits.nofile` to 1024/1024 — do not remove it.
- **The `Symfony\Component\Ldap\Ldap` service needs the literal `ldap` tag** in
  `services.yaml` — `CheckLdapCredentialsListener`'s service locator looks it up by
  that tag, not by autowiring the class.
- **Logout is CSRF-checked despite not being state-changing by convention** —
  `ALWAYS_PROTECTED_PATHS` forces the check regardless of HTTP method, since
  `LogoutListener` matches any method (skipping "safe" ones would allow a cross-site GET force-logout).
- **Functional/unit tests double LDAP with `App\Tests\Double\FakeLdap`** (password
  always literal `password`), not a live bind to `ldap` — keeps `WebTestCase` auth
  tests fast and DAMA-rollback-safe.
- **Prometheus scrapes only itself.** `_docker/prometheus/prometheus.yml` has a
  single `prometheus` job targeting `localhost:9090`; no app metrics endpoint is
  wired yet.
- **Benign log noise, do not chase:** MariaDB `io_uring_queue_init() failed with
EPERM` (WSL2), Grafana provisioning warnings, `SQLITE_BUSY` retries at startup.
- **Voter role checks must call `Security::isGranted`, never `in_array` on the token's raw roles** — `isGranted` walks `role_hierarchy` (`ROLE_TS`/`ROLE_DAS` < `MODERATOR` < `ADMIN` < `SUPER_ADMIN`); `in_array` silently breaks that for anything above the literal role tested.
- **`frontend-test`'s container mounts only `frontend/`, so the repo-root `.prettierrc` is invisible to it** — its own prettier run won't match repo style. Always lint/format via `misc-inspect` (mounts the whole repo); this has bitten multiple agents.
- **`messenger-worker`'s scheduler rebuilds its schedule only at container boot**
  (hourly recycle) — creating or editing a `DataSource`'s import schedule has no
  effect until the worker restarts; it does not poll the DB.
- **`HttpFetchGuard` denies private/loopback IP ranges by default** (SSRF guard on
  import fetches, http/https only, no redirects, 30s/20MB caps). Dev `.env` sets
  `IMPORT_ALLOW_PRIVATE_NETWORKS=1` for sibling containers — never set it outside dev.
- **`messenger_messages` needs no `schema_filter` entry** —
  `DoctrineTransport::configureSchema()` already hooks into the same schema-diff
  pass `doctrine:migrations:diff` uses.
- **`App\Service\TaskSeqAllocator::allocate()` must run before any other
  auto-increment insert in the same transaction whose ID still needs
  `Connection::lastInsertId()`** — its `UPDATE ... LAST_INSERT_ID(task_seq + 1)`
  overwrites the connection's session-local `LAST_INSERT_ID()` value. Assumes a
  dedicated per-session DB connection; a ProxySQL/MaxScale-style pooler breaks it.
  Bypasses the ORM (no `taskSeq` setter) — refresh the entity if the new value is
  needed in-memory.
- **E2E per-worker identities are `parallelIndex`-keyed, not test-keyed** — `frontend/e2e/helpers/users.ts::allocateUser` maps `role + parallelIndex` to seeded logins (`admin${idx+1}` etc.); `POOL_SIZE` (10) must stay ≤ compose's `LDAP_USERS_PER_ROLE` or allocation throws — bump both together, never just one.
- **`compose.ci.yml` is a CI-only override, never loaded locally** — layered in only via `COMPOSE_FILE` in `.gitlab-ci.yml`; drops nginx's host port publish so parallel CI jobs on one host never collide on ports 80/3306. Its `!reset []` merge key needs Compose ≥2.24 — do not backport it into local `compose.yml`.
- **E2E binary fixtures (`frontend/e2e/fixtures/{objects.xlsx,template.docx}`) have no regen script** — generated one-shot; their expected structure (columns/mapping, template placeholder tokens) is documented in `helpers/api.ts`, not reproducible from a command.
- **`_docker/ldap/bootstrap/generate-data.sh`'s `NAMES` table must stay in lockstep with `SeedDemoCommand::USERS`** — `LoginSuccessSubscriber` refreshes the local `User` mirror from LDAP `displayName` on every login, so a drifted name in either table gets silently overwritten by whichever one the user next logs in against. Nothing enforces the match automatically.
- **The e2e suite leaves undeletable projects behind** (`objlist-w4-…`, `wizard-w1-…`, … — no project delete route exists) that crowd out demo projects in list views; `app:seed:demo --fresh` only purges its own fixed demo slugs, never these. Capture `_docs/screenshots/` shots right after seeding and before running the e2e suite, not after.
