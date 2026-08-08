# Potatoe Task Manager — board members

Read by the decision-board agent: "Execution board" is the lens roster for
verdicts; "Research panel" lists lenses the board may request via a RESEARCH
outcome. Research findings return as `gap | severity | proposed default` and
are evidence, never verdicts.

Lenses are drawn from `_docs/spec.md` (the product) and `_docs/security-model.md`
(the auth/authorization reference design), not from any implementation — there is
none yet.

## Execution board

- domain designer — task immutability, work-order lifecycle, state machines
- backend engineer — Symfony, Doctrine, transactional and concurrency conventions
- security engineer — LDAP auth, CSRF, voter matrix, SSRF guard, presigned URLs
- frontend developer — React Router SPA, worker/moderator/admin flows
- tester — isolation, parallel-safe fixtures, unit/functional/e2e split

## Research panel

- field-service completeness — work-order genre expectations (dispatch, worklogs, documents)
- workflow UX — worker vs moderator vs admin task flows
- security archaeology — auth/authorization patterns, audit-trail norms for the signed-work-order model
- integration — LDAP/AD, imports, S3/seaweedfs, document generation
- operations — CI, seeding, multi-stack coexistence
