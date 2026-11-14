# Changelog

## 1.1.1

- Security (marketplace review): Send reads new file names NUL-separated, never adds a name with a
  control character (chezmoi 2.74 splits a path at a newline itself), and keeps only paths inside a
  watched folder. New files are added with `--secrets=error`; without gitleaks Send says edits are not
  scanned. git runs in the repo folder instead of `git -C` (no path on a command line).

## 1.1.0 — 2026-11-14

- New look from kit 1.2: lists in cards, the state in a tinted square (green saved, yellow to do,
  red error), theme colours followed live.
- Lighter: this machine is checked every 2 minutes (was 30 s); opening the popup and a button's
  terminal still check at once and every 3 s for a while.

## 1.0.0 — 2026-11-14

First release: bar state ↑/↓, popup with files, incoming saves, last saves, repo check; Send, Apply, Changes in a terminal; en/ru.
