# Evidence — `../agents/smoke-runner.md`

| rule anchor (quoted fragment) | what happened | when (ISO) | commit/ref |
| --- | --- | --- | --- |
| "environment-class defects are found by executing, never by reading a diff" | defects that reached no reviewer and only executing found: extension build failures, nginx body-size 413s, compose-isolation collisions in CI, flaky e2e locators | 2026-08-21 (recorded; undated) | - |
| "Never curl a container directly" | the nginx-layer defects behind the rule: nginx body-size caps, the resolver-variable upstreams, the `s3.ptm.local` alias that presigning depends on | 2026-08-21 (recorded; undated) | - |
