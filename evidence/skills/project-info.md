# Evidence — `../skills/project-info/SKILL.md`

| rule anchor (quoted fragment) | what happened | when (ISO) | commit/ref |
| --- | --- | --- | --- |
| "No `container_name:`, and `frontend` publishes no host port" | fixed container names and the published frontend port collided with the unrelated `telemetry` stack on the same host | 2026-08-21 (recorded; undated) | - |
| "only proves it post-reset" | a full implementation of the spec — including stack services, an LDAP container among them — was built, rejected and deleted; git history was purged by design, leaving the current "initial commit" as the reset point | 2026-08-21 (recorded; undated) | - |
| "carries `create_host_path: false`" | without the flag Docker created a root-owned directory named `rootCA.pem`; `generate-certs.sh` then died on `mv: … Permission denied` until it was `rmdir`-ed | 2026-08-21 (recorded; undated) | - |
| "relation \"authentik_tasks_workerstatus\" does not exist" | observed as startup noise for roughly the first 70s after a cold `up`, until server migrations finished | 2026-08-21 (recorded; undated) | - |
| "Never mount tmpfs over a subpath of a bind mount" | tmpfs over `/var/www/api/.phpunit.cache` created the directory root-owned on the host and broke the uid-1000 workflow; cost real debugging time | 2026-08-21 (recorded; undated) | - |
| "the repo-root `.prettierrc` is invisible to it" | multiple agents formatted via `frontend-test`'s own prettier and produced output that did not match repo style | 2026-08-21 (recorded; undated) | - |
