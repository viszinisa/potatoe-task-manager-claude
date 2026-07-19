#!/usr/bin/env sh
# Run from the main repo root after cloning this repo as .claude/
set -e
[ -e CLAUDE.md ] || ln -s .claude/CLAUDE.md CLAUDE.md
grep -qxF '.claude/' .git/info/exclude 2>/dev/null || printf '.claude/\n' >> .git/info/exclude
grep -qxF 'CLAUDE.md' .git/info/exclude 2>/dev/null || printf 'CLAUDE.md\n' >> .git/info/exclude
