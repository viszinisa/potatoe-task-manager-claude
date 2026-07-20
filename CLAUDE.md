# Conversation settings

- Every reader of anything written here — me, and any agent reading a doc, skill, comment or commit message — is tech-savvy. Keep answers short unless I ask for more; skip basic explanation, obvious justification, and elaboration of a point already made. State the conclusion and the non-obvious reason, nothing else. This applies to conversational answers and to every file written into the repo.
- Do not narrate intermediate steps while working — work in the background and report only the final outcome, or prompt me if you genuinely need my input.
- Do not exit this project's directory (`/home/artis/work/potatoe-task-manager`). You do not need my permission to edit project files.
- Use 4-space indentation in all files.
- Comment only very important, non-obvious code, one short line whenever feasible. No narrative/explanatory comment blocks.
- Always use ISO 8601 date/time formats (`YYYY-MM-DD`, `YYYY-MM-DD HH:MM:SS`, or `YYYY-MM-DDTHH:MM:SSZ` for machine-readable UTC) — in code, logs, docs, and responses. Never slash formats, month names, or other locale formats.
- After changing compose.yml, compose.*.yml, or anything under `_docker/`, verify the change actually works (rebuild/restart the affected service, check logs and/or the relevant metrics endpoint) before reporting the task done.
- Pin Docker images in compose.yml to the newest available version/tag (explicit, never a floating `latest`) unless that creates an unresolvable conflict (e.g. a real compatibility break with another pinned component) — check what is actually current rather than trusting an existing pin or taking the first newer tag that works.
- Once a plan is fully implemented, retire its source: delete the plan file, or strike the item from the list it came from (future ideas, backlog, improvement plan). Same for the merged/abandoned case — a plan that is no longer pending does not stay on disk. Git keeps the history — but only if the file is **tracked**: check with `git ls-files --error-unmatch <file>` before deleting, and commit an untracked plan first, otherwise the delete is unrecoverable. Retiring is the orchestrator's call at the end of the whole plan, never a sub-agent's — a sub-agent finishing phase N does not know phases N+1.. are outstanding, so it never deletes or strikes anything outside its own phase.
- Commit after each phase/task completes, not in one lump at the end. Uncommitted work is unrecoverable if something later deletes or overwrites it, and a large mixed tree cannot be split cleanly afterwards (interleaved edits to one file by several phases can only be committed together).
    - **The orchestrator commits, sub-agents do not.** The git index is shared mutable state across the worktree: two agents staging concurrently means one sweeps the other's half-written files into its commit. Sub-agents report their changed paths; the orchestrator commits them as each report lands.
    - Never `git add -A`, `git add .`, or `git commit -a` while any sub-agent is running — stage explicit paths only. Blanket staging is what turns a parallel run into a corrupted commit.
    - Group by coherent change, not by file count. Two fixes that only pass because they cancel each other out belong in one commit; splitting them yields a commit that hides a real defect.
    - For genuinely independent parallel work that will not interleave in the same files, prefer giving each sub-agent its own worktree (`isolation: "worktree"`) over serialising commits.
    - **Finishing work means committing AND pushing BOTH repos** (see "Two repos" below), not just the outer one. Check `git status` in `/home/artis/work/potatoe-task-manager` and in `/home/artis/work/potatoe-task-manager/.claude` before declaring done. The outer repo has no upstream tracking, so its first push is `git push -u origin main`; `.claude` already tracks `origin/main` and takes a plain `git push`.

## Two repos

- **Outer** `/home/artis/work/potatoe-task-manager` → `git@github.com:viszinisa/potatoe-task-manager.git` — the stack itself (compose, `_docker/`, `api/`, `frontend/`, README).
- **Nested** `/home/artis/work/potatoe-task-manager/.claude` → `git@github.com:viszinisa/potatoe-task-manager-claude.git` — agent config only: skills, hooks, bin, agents, and `CLAUDE.md` (the repo-root `CLAUDE.md` is a symlink to `.claude/CLAUDE.md`, so the `.claude` repo owns it).
- The outer repo's `.git/info/exclude` lists `.claude/` and `CLAUDE.md` **on purpose** — it keeps the outer repo from swallowing the nested one. Never "fix" this by tracking `.claude/` in the outer repo, converting it to a submodule, or removing those exclude lines.
- Consequence: any change under `.claude/` — a skill, hook, agent definition, or `CLAUDE.md` itself — is **invisible to `git status` in the outer repo** and must be committed in the `.claude` repo.
- Whenever the stack's architecture, data flow, ports, or access model changes, update **or prune** README.md to match before ending the turn. Pruning is as much a part of this rule as adding — a change that obsoletes an existing line means deleting that line, not appending a newer one below it. (The `project-info` skill is covered by the general skill rules in `~/.claude/CLAUDE.md`.)
- README.md is a concise operator/newcomer doc, not a changelog or a history of the stack. Same discipline as the skills below: **soft cap 250 lines** (`wc -l`), record only what cannot be re-derived from the code, prune at least as much as you add. Never dates, "formerly X", evolution narrative, completed-item entries, per-endpoint/per-flag reference tables that restate the controllers or `-h` output, or obvious justification. Keep: what the stack is, data flow, services/ports/access model, how to run it and its tests, non-obvious invariants and traps, a pointer to `.claude/skills/`.
    - Over the cap with nothing genuinely prunable left, split rather than delete something load-bearing: the overflow becomes a self-contained topic doc under `_docs/`, and README keeps a one-line pointer to it. Natural seams are operations/runbook, benchmarking/scaling, and testing — none is needed to understand what the stack is. Splitting is the last resort, not the first move: prune first, and never split to dodge the cap while leaving re-derivable content in place.
- The general rules for creating, sizing and maintaining skills live in `~/.claude/CLAUDE.md`. Skill files belong to the nested `.claude` repo and must be committed and pushed there.
- If a linter/formatter (php-inspect, misc-inspect, ...) repeatedly conflicts with the code you naturally write, or its rewrite breaks functionality (e.g. non-idempotent or corrupting output), stop hand-fixing files: find the config rule/parameter responsible and amend it to a more reasonable value (`.prettierrc`, `api/.php-cs-fixer.dist.php`), noting why. Then re-run the linter to keep the repo lint-clean.
- Art signals make completions and blocked turns stand out in console output. NEVER hand-type or hand-concatenate this art — the filler is U+3000 (invisible), so hand-typed rows silently lose their trailing padding, which has produced misaligned art more than once. Run the script and paste its output verbatim; it is the only correct source.
    - `.claude/bin/agent-art.sh tick 1` when a task finishes, `tick 2` when the finished task produced a report/findings, `tick 3` when the entire assignment is complete.
    - `.claude/bin/agent-art.sh question` — exactly one question icon at the end of any response that ends by asking me something and waits for my answer.
    - **HARD RULE:** every main-thread reply ends with exactly one signal, pasted by the model itself — `question` when the reply waits for my answer, `tick 3` when the assignment is complete. No hook emits this; forgetting it or emitting both is a broken turn.

## Frontend

- The frontend is a React SPA using React Router. In production it is a static build only (no Node server) — served as static assets.
- In dev, run it via the React dev server (built-in dev mode / Node), in a dedicated `node` container in the dev stack.
- Styling is Tailwind v4, wired through the `@tailwindcss/vite` plugin with CSS-first config — `@import "tailwindcss"` (plus `@theme` for customisation) in the stylesheet. Never `tailwind.config.js` + a PostCSS pipeline; that is the v3 setup and does not apply here.
- Icons are FontAwesome via the tree-shakeable React component packages (`@fortawesome/react-fontawesome` + `@fortawesome/fontawesome-svg-core` + the icon packs). Never the monolithic free CSS package.
- Do not install npm packages indiscriminately. Add only reasonable, well-justified dependencies.

## Testing

- UI/E2E tests use Playwright (`@playwright/test`), living in `frontend/e2e/`. Run in the dedicated `playwright` compose service (profile `test`), never on the host.
- Component/lib unit tests use vitest + React Testing Library, in the `frontend-test` service (profile `test`).
- PHP code is tested with PHPUnit. Run inside the container; sources are bind-mounted, so no rebuild is needed:
    - `docker compose --profile test run --rm api-test vendor/bin/phpunit`
- API endpoint tests use Symfony `WebTestCase` (functional tests against the booted kernel), not HTTP calls to a running stack.
- Every UI test must run in parallel, on dedicated/parallel GitLab CI runners: no shared mutable state, no dependence on execution order, no fixed record IDs or names another test could touch, no global setup another test relies on. Isolation comes from each CI worker having its own environment and database, not from in-test data namespacing. Read-only assertions preferred.
- PHP tests must be isolated too: no ordering dependence, DB state rolled back per test (DAMA doctrine-test-bundle in the API).
- New features get tests; do not report a feature done without them.

## Model roles: Fable orchestrates, sub-agents execute
*HARD RULE.* In this project the main conversation always runs on Fable
(claude-fable-5). Fable's role is strictly
*project manager and orchestrator*:
- *Fable does NOT execute tasks itself.* It plans, decomposes work,
  delegates, reviews results, and reports back to the user.
- *All actual work is delegated to sub-agents via the Agent tool* with an
  explicit model override:
  - model: "opus" — complex work: multi-step implementation, debugging,
    architecture-sensitive changes, anything requiring deep reasoning.
  - model: "sonnet" (Sonnet 5) — routine work: searches, lookups, file
    reads, simple edits, running commands, plugin/skill operations, drafting
    messages and documents.
- *Run independent sub-agents in parallel* (multiple Agent calls in one
  message) whenever tasks don't depend on each other.
- *The only exception:* Fable may investigate details directly when there
  is a genuine challenge — a sub-agent failed or returned contradictory
  results, the problem is too subtle to delegate safely, or precise judgment
  on conflicting evidence is needed. This is the exception, not the norm;
  return to delegating as soon as the blocker is understood.
- Trivial conversational replies (answering a question from context, a
  one-line clarification) need no sub-agent — but anything that touches
  files, tools, or external systems gets delegated.
Rule of thumb: if Fable is about to run a tool to do work rather than to
coordinate work, stop and delegate it instead.

## Sub-agent definitions (`.claude/agents/`)

- The general rules for creating, reporting, sizing and retiring agents live in `~/.claude/CLAUDE.md`. Only this project's specifics are recorded here.
- Agent files belong to the nested `.claude` repo, so they are invisible to `git status` in the outer repo and must be committed and pushed there.
- **`smoke-runner`** runs at every section boundary: brings the stack up, exercises the section's primary endpoint **through nginx**, tears down. It is what discharges the "verify compose/`_docker/` changes by actually running them" rule in Conversation settings, which until now had no enforcer — a section that touched the stack is not done until `smoke-runner` has passed.

## Plan execution

- The plan → sub-plan → section → task gate ladder, the deferred ledger, and merge gating are defined by the generic `plan-pipeline` skill (`~/.claude/skills/plan-pipeline/SKILL.md`). It is the authority; do not restate or fork its contract here.
