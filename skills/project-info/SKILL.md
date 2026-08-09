---
name: project-info
description: Background, locked decisions and known traps for the Potatoe Task Manager Docker Compose stack (nginx vhost routing, Symfony API scaffold, MariaDB, React Router SPA, seaweedfs, Prometheus, Grafana). Use when working on compose.yml, anything under _docker/, api/, the frontend/ SPA, or the README in this project.
---

# Potatoe Task Manager

Docker Compose dev stack. Services, ports, images and mount rationale are in
`compose.yml` and its comments — read those. Below is only what the files do
not say.

## Current state

- **Plan `v1-product` is under execution on the `plan/v1-product*` branches**,
  identity (Authentik) first. Landed so far: the `users`/`user_group`/`api_token`
  schema, OIDC login + API-token layer under `api/src/Security/`, the
  `/api/v1/auth/{oidc,oidc/callback,me,logout}` endpoints, and the messenger/
  scheduler skeleton. Everything else is unbuilt — `frontend/app` is a single
  welcome route, no domain code, storage layer or admin surface to reference.
- **`_docs/spec.md` is the product spec** driving `v1-product`; check the plan
  file for what section is in flight before assuming a spec area is built.
- A full implementation of the spec was built, rejected and deleted — including stack
  services (an LDAP container existed once). **Git history itself was purged by design**:
  the current "initial commit" is a reset point, so `git log`/`git log -S` proving
  something "never existed" only proves it post-reset — never state it stronger. What was
  worth keeping is distilled into `_docs/security-model.md` (auth/authorization reference
  design); everything else is gone deliberately, so do not go looking for it.

## Locked decisions

- **No `container_name:`, and `frontend` publishes no host port** — both collided
  with the unrelated `telemetry` stack. Top-level `name: ptm` gives `ptm-<service>-1`.
  Do not re-add either.
- **nginx's own upstream hops — every conf.d upstream and the `:3306` stream — use
  compose service DNS.** Every other inter-service hop dials the public `*.ptm.local`
  name over TLS — `extra_hosts` → `host-gateway` (the `x-ptm-hosts` anchor) sends it
  out to the host and back through the edge, modelling services that won't share a
  cluster. `api`/phpMyAdmin/Grafana reach the DB at `mysql.ptm.local:3306`, prometheus
  self-scrapes `https://prometheus.ptm.local`. Never add nginx network aliases.
  **Carve-out:** `authentik-server`/`authentik-worker` → `authentik-postgres` runs
  over plaintext compose service DNS, not `*.ptm.local` — there is no
  `postgres.ptm.local` edge, and a platform service's own backing store is the
  same class as nginx's own upstream hops, not an inter-service hop. **No
  Redis/Valkey for Authentik, ever** (≥2025.10 stores cache/sessions in
  PostgreSQL) and **no LDAP service locally** (spec makes LDAP prod-only
  external) — do not "complete" the stack with either.
  **Second carve-out:** `api` → `mailpit:1025` over plaintext compose service DNS, not
  `mail.ptm.local` — SMTP is not HTTP, so nginx cannot terminate it (only the HTTP UI/API
  is proxied at `mail.ptm.local`). Never add an SMTP vhost to nginx for this.
- **nginx is the sole TLS edge** — `:443` for every vhost from one `ssl_certificate` in
  `http{}`, `:80` is a catch-all 301, hops behind the edge stay plaintext (no
  `fastcgi_ssl` exists). **No HSTS, deliberately:** `.local` pinning is painful to undo.
  MariaDB is the exception: nginx cannot terminate its `:3306` stream (MySQL greets in
  plaintext before the in-protocol TLS upgrade, so `ssl_preread` breaks it), so it
  serves its own TLS end-to-end with `require_secure_transport = ON`.
- **Every nginx upstream uses the resolver-variable pattern** (`resolver 127.0.0.11
valid=10s;` + `set $x_upstream ...;`), not a static `proxy_pass`/`fastcgi_pass` —
  static targets refuse to start if the backend is down at boot; the variable form
  defers DNS to request time, which is also why nginx carries no `depends_on`. Never
  "simplify" either back.
- **`dev1`–`dev5.ptm.local` are reserved, unclaimed vhost slots** — add a conf.d file
  when claiming one; never reuse a fixed service name for ad-hoc work.
- **API auth is an opaque token, not a session (spec amendment A-9).** Two firewalls in
  `security.yaml`, order load-bearing: `auth` (`^/api/v1/auth/oidc`, `stateless: false`,
  carries the drenso `oidc:` listener; its session only ferries `state`/`nonce`) is declared
  **before** `api` (`^/api/v1`, `stateless: true`, `access_token` authenticator). The
  credential is the httpOnly `API_TOKEN` cookie, then `Authorization: Bearer`; only its
  sha256 is stored (`api_token`), so revocation is a row delete. **Never move the `logout:`
  key onto `api`** — LogoutListener (-127) outranks AccessListener (-255) on a non-lazy
  firewall, which turns the endpoint into an anonymous 302 for everyone.
- **`GET /api/v1/auth/me` roles are AS-HELD, not hierarchy-expanded** — floored
  to `ROLE_EMPLOYEE` only; a `ROLE_MODERATOR` check must enumerate every
  granting role, never a bare `.includes()`.
- **`App\Scheduler\DefaultSchedule` is the only `#[AsSchedule]` class** — attach every
  `RecurringMessage` to it. A duplicate `'default'` is a hard container-compile error, but a
  _second name_ compiles silently and never runs: `api-worker` consumes only
  `async scheduler_default`. Messenger transports run `auto_setup=false`, so any new transport
  needs its own migration, never worker-issued DDL.
- **seaweedfs S3 auth lives in `_docker/seaweedfs/s3.json`**, mounted read-only into
  the container; `s3.ptm.local` proxies it 1:1 (SigV4 needs `Host` passed through
  unchanged, see `s3.conf`). Any future presigning must be signed against that
  hostname, since the browser — not `api` — consumes the URL.

## Traps

- **Cert material is gitignored — `_docker/nginx/ssl/` holds only `.gitkeep` on a fresh
  clone.** Run `_docker/nginx/generate-certs.sh` before any `up` or smoke leg: missing
  certs kill nginx outright and abort mariadb (`Failed to setup SSL`), cascading to
  `api`. Every cert mount carries `create_host_path: false` so `up` fails with `bind
source path does not exist`; without it Docker creates a root-owned _directory_ named
  `rootCA.pem`, after which the generate script dies on `mv: … Permission denied` until
  it is `rmdir`-ed. The key is mode 0644 on purpose (mariadb is uid 999), and
  `_docker/nginx/ssl/` is mariadb's cert source despite the `nginx/` path.
- **`_docker/mariadb/conf.d/` is bind-mounted, so a `.cnf` edit arms at the next
  restart** — an unloadable `ssl` setting aborts the server, it does not degrade.
  Sequence such edits with a controlled restart; never leave one sitting in the tree.
- **Grafana reads the CA at provisioning time** (`secureJsonData.tlsCACert: $__file{}`),
  not per query — regenerating `rootCA.pem` needs `docker compose restart grafana`.
  `jsonData.tlsAuthWithCACert` is the mode selector that gates the read; `tlsCACertFile`
  does not exist in this Grafana.
- **nginx's `X-Forwarded-Proto` injection is unconditional**, so a client cannot strip
  it — an A/B "with and without the header" test through the edge is not a real A/B.
- **Playwright's `use.ignoreHTTPSErrors` propagates to the built-in `request` fixture.**
  A CA-trust assertion needs its own strict context —
  `request.newContext({ ignoreHTTPSErrors: false })` — which verifies via
  `NODE_EXTRA_CA_CERTS`; against the default fixture the assertion is vacuous.
- **prettier cannot parse `.conf`/`.cnf`/`.env`** — those stay unlinted; shellcheck
  (`tools` profile) covers `.sh`, `nginx -t` is the de-facto nginx check.
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
EPERM` (WSL2), Grafana provisioning warnings, `SQLITE_BUSY` retries at startup,
  and Authentik worker logging `relation "authentik_tasks_workerstatus" does not
exist` for its first ~70s until server migrations finish.
- **Authentik's `/data/media` is a symlink to `/media`** — mounting the
  `authentik_media` volume at `/data` persists nothing; it must mount at `/media`.
- **A failing Authentik blueprint is invisible**: containers stay healthy, the worker
  logs `apply_blueprint … Task finished, exc: null`, and only
  `authentik_blueprints_blueprintinstance.status` turns `error` — a broken _edit_ still
  serves the old config since previously applied objects stay intact. Assert
  `/application/o/ptm/.well-known/openid-configuration`, never health. Blueprint passwords
  apply on create only. Files live in `_docker/authentik/blueprints/` → `/blueprints/custom`.
- **Every new vhost must overwrite `X-Forwarded-For` with `$remote_addr`, never
  append via `$proxy_add_x_forwarded_for`** — nginx is the outermost proxy, so
  there is no upstream hop to preserve and appending lets a client spoof the
  header. `authentik.ptm.local` follows this; copy it, not an append pattern
  from elsewhere.
- **`composer recipes:update symfony/scheduler` recreates `api/src/Schedule.php`
  from the flex lock**, duplicating `#[AsSchedule('default')]` alongside
  `DefaultSchedule.php` — the container then hard-fails compilation. Delete the
  regenerated file again; never merge it.
- **`oidc/callback`'s controller action never runs on a real callback** — drenso's
  listener intercepts first; the route exists only so `RouterListener` doesn't 404
  before the firewall. Success (`OidcLoginSuccessHandler`) mints an opaque
  `ApiToken` → `API_TOKEN` httpOnly cookie → `session->invalidate()` (drenso's
  `OidcToken` otherwise leaves raw IdP tokens/claims sitting in the session file)
  → 302 to the stashed return path.
- **`ReturnPathStash` accepts only `^/(?![/\\])`** — rejects absolute URLs,
  protocol-relative `//` and normalized `/\`, guarding the post-login redirect.
- **`/api/v1/auth/logout` is POST-only** — an anonymous GET 405s at routing,
  never reaching the firewall; an "anonymous → 401" test must hit `/auth/me`.
