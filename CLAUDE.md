# CLAUDE.md

@AGENTS.md

All project rules live in AGENTS.md (imported above) so every agent shares one source of truth.
Edit AGENTS.md, not this file, when project rules change.

## Claude Code notes

- Before finishing a change to `netwatch.sh`, run `bash -n netwatch.sh` and, if available,
  `shellcheck -s bash netwatch.sh`.
- For dashboard changes, run the fake-data render test from AGENTS.md and report the
  widest line length.
- Personal, machine-specific notes go in `CLAUDE.local.md` (git-ignored).
