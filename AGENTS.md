# AGENTS.md

Guidance for AI coding agents working on **netwatch**.

## What this project is

netwatch is a single-file Bash tool that turns a spare Android phone running
Termux into an always-on home network watchdog and desk display.

- `netwatch.sh` (no args) runs one scan. It is called hourly by cron.
- `netwatch.sh show` runs a live terminal dashboard meant to stay on screen 24/7.

A scan discovers LAN hosts and open ports with nmap, diffs them against a
cumulative baseline, tracks the WAN IP and UPnP port forwards, logs events,
and raises an Android notification on anything new.

## Target runtime (read this before changing anything)

The primary target is deliberately constrained. Do not assume a normal Linux box.

- **Termux on Android 10, non-root.** Never require root or `sudo`.
- **Unprivileged nmap only.** `-sS`, `-sU`, `-O` and ARP discovery are unavailable.
  Use `-sT` and `--unprivileged`.
- **ARP table may be blocked.** `ip neigh` and `/proc/net/arp` can fail on Android 10+.
  Any MAC-based feature must degrade gracefully when they do.
- **Shebang** is `#!/data/data/com.termux/files/usr/bin/bash`. Keep it.
- **PATH** is set explicitly at the top because cron runs with a minimal environment.
- **Bash 5 + bionic libc + Termux coreutils.** GNU-style `sed`, `date -d`, `stat -c` are fine.
  Avoid tools not installed by default unless they are optional and checked with `command -v`.
- **Optional dependencies** (`termux-api`, `miniupnpc`) must never be required. Missing ones
  disable a feature silently; they must not crash the script or hang it
  (wrap Termux:API calls in `timeout`).
- **Phone hardware:** narrow portrait screen (~45-50 columns), curved screen edges,
  AMOLED panel, on charge 24/7.

Runtime data lives in `$HOME/netwatch` (`BASE`), separate from this repository.
Never write runtime data into the repo.

## Repository layout

```
netwatch.sh                  the tool (single file, by design)
README.md                    user-facing docs
CHANGELOG.md                 release notes (Keep a Changelog)
LICENSE
AGENTS.md / CLAUDE.md        agent instructions
examples/labels.txt          sample IP -> label file
examples/known_macs.txt      sample MAC allowlist
examples/start.sh            sample Termux:Boot script
docs/                        screenshots (fake data only)
tests/                       stubs + test runner (planned)
.github/workflows/ci.yml     syntax, shellcheck, tests (planned)
```

Keep netwatch a single file. Users install it by copying one script to a phone.
Do not split it into modules or add a build step.

## Hard rules

1. **LF line endings only.** CRLF breaks the shebang on Termux (`bad interpreter: ^M`).
   `.gitattributes` enforces this; do not override it.
2. **No real network data in the repo.** No real public IPs, MAC addresses, hostnames,
   scan output, or screenshots containing them. In docs and tests use
   `203.0.113.0/24` (RFC 5737) for WAN examples and `192.168.35.0/24` for LAN examples.
3. **Scan only networks the user owns.** Do not add features that target networks other
   than the configured `SUBNET`, evade detection, or attack hosts.
4. **UI text is English.** Dashboard, logs, notifications and comments are in English.
5. **Event log format is a contract.** Each line in `alerts.log` is
   `YYYY-MM-DD HH:MM:SS TAG detail...`. The dashboard parses it by position.
   Tags are UPPER_SNAKE_CASE (`NEW_HOST`, `NEW_PORT`, `UNKNOWN_MAC`, `WAN_CHANGED`,
   `NEW_UPNP`, `SCAN_EMPTY`). Add new tags freely; do not change the line format.
6. **Bump `VERSION`** in `netwatch.sh` and add a `CHANGELOG.md` entry for user-visible changes.

## Dashboard rendering rules

The dashboard is the part most likely to break visually. Follow these when editing it.

- `LC_ALL=C.UTF-8` is set so `${#var}` counts characters, not bytes. Keep it.
- Compute padding and truncation on **plain text**, then wrap colors around it.
  Never measure a string that contains ANSI escapes.
- Every rendered line must fit within `BW` (box width). Use `fit` to truncate.
- `printf '%-Ns'` pads by bytes, so only use it on ASCII. Use ASCII for labels and
  placeholders (`-`, not `·`).
- Glyphs in use: box drawing (`╭─╮│╰╯`), blocks (`▁`-`█`), braille spinner, `●○❯▌…°·`.
  Do not introduce double-width characters (CJK, most emoji).
- Lines are prefixed with `PADX` and the frame starts after `MARGIN_Y` blank lines
  to stay clear of the curved edges and top bezel.
- Redraw by moving the cursor home (`\e[H`), ending lines with `\e[K` and the frame with
  `\e[J`. Do not `clear` every frame; it flickers.
- The loop ticks every second. Keep per-tick work cheap: reload data only when
  file mtimes change, poll the battery every 30 ticks.

## Coding conventions

- Bash, 2-space indent, `local` for function variables, quote all expansions.
- Prefer small helpers over clever one-liners; this is read on a phone over SSH.
- No `set -e`: a failed optional step must not abort the scan.
- Comments explain *why*, briefly, in English.

## Testing

There is no phone in CI, so test with fake data and stubs.

```bash
bash -n netwatch.sh               # syntax
shellcheck -s bash netwatch.sh    # lint (fix or justify warnings)
```

Scan path: put stub `nmap` and `curl` scripts first on `PATH` that write canned
`-oG` output, set `HOME` to a temp dir, run the scan twice, and check
`summary.txt`, `alerts.log`, `seen_*.txt` and `runs/*/new_hosts.txt`.

Dashboard: seed a temp `BASE` with a fake run, then
`timeout 3 bash netwatch.sh show < /dev/null > out.txt`, split the output on `\e[H`,
strip ANSI escapes, and assert every line length is `<= BW + 2 * MARGIN_X`.

## Commits

Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`.
Keep commits focused; one behavior change per commit.
