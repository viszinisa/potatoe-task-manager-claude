# Evidence sidecars

Per-file record of what each agent/skill rule in this repo actually cost or caught, kept out of the files themselves so the loaded byte budget carries rules, not tallies.

- One file per config file: `skills/<skill-name>.md` for `../skills/<skill-name>/SKILL.md`, `agents/<agent-name>.md` for `../agents/<agent-name>.md`.
- Format: frontmatter-free, one append-only table — `rule anchor (quoted fragment) | what happened | when (ISO) | commit/ref`. Append rows; never rewrite or delete one.
- `when` is the ISO date the event happened; when only the recording date is known (a row carried in from a loaded file that never dated it), write `<ISO> (recorded; undated)` — never a guessed event date, never `-`. Other unknown fields stay `-`.
- `rule anchor` quotes a fragment of the live rule verbatim, so a renamed or reworded rule is visibly orphaned.
- Read by `agent-improver` and `plan-retrospective` when judging whether a rule still earns its line: no rows = prune candidate, repeat rows = the case for keeping it.
- **Never auto-loaded.** No agent reads these at spawn; they are opened deliberately, one file at a time, during a prune or retrospective pass.
- A seed file with an empty table is normal — it is the target a pruner appends to.
