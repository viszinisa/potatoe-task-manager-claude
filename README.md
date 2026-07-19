# potatoe-task-manager-claude

Claude Code configuration for the Potatoe Task Manager stack (`potatoe-task-manager`). Lives as `.claude/` inside the main repo working directory but is its own git repo, so agent tooling stays out of the main repo's history.

Cloning this repo alone is not enough — the main repo is the working tree it configures. Get both.

## Layout

- `CLAUDE.md` — project instructions; symlinked to the main repo root as `CLAUDE.md`
- `skills/` — project skills, one dir per skill with a `SKILL.md`
    - `basic-information-about-project/` — stack background, locked decisions, traps
    - `lint-code/` — how to run php-inspect / misc-inspect
- `bin/agent-art.sh` — console art signals (`tick 1|2|3`, `question`)
- `settings.json` — shared settings: model, marketplaces, enabled plugins, Bash permission allowlist
- `settings.local.json` — machine-local overrides; untracked here, and also ignored by the main repo's `.gitignore`
- `setup.sh` — symlink + git-exclude wiring, idempotent

## Committed vs per-machine

| Path                          | Scope                       | Contents                                                                        |
| ----------------------------- | --------------------------- | ------------------------------------------------------------------------------- |
| `CLAUDE.md`                   | committed                   | Project hard rules (style, docker verification, orchestration policy)           |
| `.claude/settings.json`       | committed                   | `model`, `extraKnownMarketplaces`, `enabledPlugins`, shared `permissions.allow` |
| `.claude/skills/`             | committed                   | Project-vendored skills                                                         |
| `.claude/bin/`                | committed                   | `agent-art.sh` — completion/question art generator                              |
| `.mcp.json`                   | committed (**main** repo)   | Project MCP servers (Playwright)                                                |
| `.claude/settings.local.json` | per-machine, gitignored     | Personal permission overrides on top of the committed allowlist                 |
| `~/.claude/settings.json`     | user scope, never committed | Personal theme, `statusLine`, credentials                                       |

Settings precedence: enterprise policy > CLI args > `.claude/settings.local.json` > `.claude/settings.json` > `~/.claude/settings.json`.

## Prerequisites

- Docker with Compose v2 (`docker compose`, not `docker-compose`)
- git, SSH access to both GitHub repos
- Claude Code CLI
- Nothing else on the host — all toolchains (PHP, Composer, Node, npm, PHP-CS-Fixer, prettier, Playwright) run in containers

## Setup

```bash
git clone git@github.com:viszinisa/potatoe-task-manager.git
cd potatoe-task-manager
git clone git@github.com:viszinisa/potatoe-task-manager-claude.git .claude
.claude/setup.sh
```

`setup.sh` symlinks `.claude/CLAUDE.md` to `./CLAUDE.md` and appends `.claude/` and `CLAUDE.md` to `.git/info/exclude`. That exclude file is **local and untracked** — a fresh clone of the main repo never has those lines, which is exactly why `setup.sh` must run before the first `git status` in the main repo, or both paths show up as untracked noise.

Then run `claude` from the main repo root. First start prompts to trust the marketplaces in `extraKnownMarketplaces` and to approve `.mcp.json` — accept both, declining either leaves plugins/MCP tools unavailable for the session. Plugins under `enabledPlugins` install automatically from the trusted marketplaces; verify with `/plugin` (installed + enabled) and `/mcp` (Playwright server connected).

## What the repo ships, and why

- `CLAUDE.md` — always loaded into context. Carries the project's hard rules, including the Fable-orchestrates / sub-agents-execute model policy: the main conversation plans and delegates, work goes to sub-agents via the Agent tool with an explicit `model` override.
- `skills/basic-information-about-project` — stack background and the place locked decisions and known traps get recorded. Currently a stub: the project is new and has neither yet.
- `skills/lint-code` — exact `php-inspect` / `misc-inspect` invocations, one per file type, plus the non-idempotent-markdown prettier trap.
- `bin/agent-art.sh` — generates the tick/question console art `CLAUDE.md` requires after task completion. Never hand-typed: the filler character is U+3000 (invisible), which silently drops from hand-typed rows.
- `settings.json` — pins the model to `opus`, declares the three third-party marketplaces and the enabled plugin set, and allowlists the Bash commands agents run constantly (docker/compose) so they do not prompt.
- `setup.sh` — the only thing standing between a fresh clone and a main repo that thinks `.claude/` is untracked project source.

## Adding a plugin or skill

Project-wide: edit `settings.json` (`extraKnownMarketplaces` for a new marketplace, `enabledPlugins` for the plugin), commit here. Teammates pick it up on their next `claude` start.

Personal-only: put it in `~/.claude/settings.json` instead — it never lands in a repo.

## Known limitation

Plugin marketplaces (`extraKnownMarketplaces`) are tracked at git HEAD — no version pinning, no lockfile. A marketplace-side plugin update changes behavior for every developer on their next `claude` start, with no diff to review. The only way to freeze a capability against this is to vendor it into `skills/`, as this repo already does for its own two skills.

## Notes & traps

- Two repos, two histories. `git status` inside the main repo never shows `.claude/` changes — `cd .claude` (or `git -C .claude`) to commit config work.
- The root `CLAUDE.md` is a symlink into this repo. Editing it edits this repo. Do not replace it with a real file.
- `settings.local.json` is the only per-machine thing here. Anything committed to `settings.json` applies to every clone.
- Deleting `.claude/` without also removing the `.git/info/exclude` lines leaves the main repo silently ignoring a future real `.claude/`.
- `.mcp.json` sits at the main repo root and is tracked by the **main** repo, not here.
- Main repo doc worth reading next: `README.md` (services, ports, how to run it and its tests).
