# Changelog

## 1.3.0

- **First run in the widget.** Without chezmoi, or without a repo, the popup shows the step to take
  and a button for it: *Install chezmoi* (through Omarchy's package command, in a terminal), then
  *Connect a repo* (paste its address, or start an empty one). Nothing is applied until you press
  Apply. `omarchy plugin add … --enable` is the whole installation; no setup before enabling.

## 1.2.1

- A landscape banner as the marketplace preview (the card crops a strip from the centre, a tall popup
  screenshot showed only its blurred top); a shorter description that says what the widget is first;
  the README shows the popup in both languages.

## 1.2.0 — family look and audit

- The family look (kit 2). The popup is built the first time it opens. Shortcuts work on a Russian layout.
- **After the first Send the widget polled every 3 s forever** (a binding on the clock never
  re-evaluated). It is a flag with a timer now, and only Send and Apply start it.
- Both bars share one reading under a lock, and one `git fetch` serves both.
- Send: a failed `chezmoi status`/`unmanaged` stops it instead of reading as "nothing to send"; without
  gitleaks it lists the edited files and asks before sending them unscanned; a watched folder must be
  inside the home folder; paths are read absolute, so a custom destination works.
- A file Send will leave out (a folder on its way is not yours alone) is marked in the popup and not
  counted in ↑.
- Compare keeps the repo's version in `$XDG_RUNTIME_DIR`, removes it when the window closes, and falls
  back to the right diff direction. Opening and comparing run without a shell parsing the path.
- The repo name never shows credentials (`@` in a password, a `?query`); odd line breaks in a file name
  no longer forge rows; the shared state folder is used only when it is the user's alone.
- A file deleted here is not offered to open or compare. Removed unused texts.

## 1.1.3

- Security (marketplace review): Send no longer runs a bare `chezmoi re-add`. It re-adds only the
  files `chezmoi status` reports as edited here, and only when every folder from the home folder down
  to the file is the user's own, not writable by group or others, and not a link — the same rule new
  files already had. Others are skipped with a message.
- `DOTFILES_SAVE=1` is set during a Send, so a chezmoi `status` pre-hook can refresh generated files then only.

## 1.1.2

- Security (marketplace review): a new file is added only when every folder from the home folder down
  to it, and every folder inside a new folder, is the user's own, not writable by group or others, and
  not a link — nobody else can swap one for a link between the check and chezmoi's read. Others are
  skipped with a message.

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
