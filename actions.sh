#!/usr/bin/env bash
# What the Dotfiles widget's buttons run, in a terminal so chezmoi can ask.
#   actions.sh save             re-add edits, add new files in dotfiles.watch, commit, push
#   actions.sh apply            chezmoi update: pull the repo and apply it here
#   actions.sh diff             what is not saved here, then what came from the repo
#   actions.sh diff local PATH  one file: the edit made on this machine
#   actions.sh diff pending PATH  one file: what apply would write
#   actions.sh compare local|pending PATH   the repo's version beside the file on disk, in
#                               Meld, VSCodium or VS Code (no terminal); a
#                               coloured diff in a terminal when none is installed
# DOTFILES_LANG=ru switches the messages to Russian. CHEZMOI=path picks the binary.
set -uo pipefail

ru() { [[ ${DOTFILES_LANG:-} == ru ]]; }
say() { if ru; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
fail() { say "$1" "$2" >&2; exit 1; }

cz=${CHEZMOI:-$(command -v chezmoi)} || true
[[ -n $cz && -x $cz ]] || fail "chezmoi is not installed" "chezmoi не установлен"
src=$("$cz" source-path) || fail "chezmoi has no source repo (run chezmoi init)" "у chezmoi нет репо (сделай chezmoi init)"
# git runs in the repo instead of taking it as `-C <path>`: one path less on
# command lines, which any local account can read. (chezmoi itself still gets
# the files it works on as arguments; it has no other way to take them.)
g() { (cd "$src" && git "$@"); }

# Folders under dotfiles.watch in chezmoi data that exist on this machine.
watched() {
  "$cz" data --format=json | python3 -I -c '
import json, os, sys
home = os.path.realpath(os.path.expanduser("~"))
for p in (json.load(sys.stdin).get("dotfiles") or {}).get("watch") or []:
    p = os.path.realpath(os.path.expanduser(str(p)))
    # A folder inside the home folder, never the home folder itself or
    # anything outside it: the list comes from the repo, and "~" would mean
    # "add every file I have".
    if os.path.isdir(p) and p.startswith(home + os.sep): print(p, end="\0")'
}

# A folder only its owner can change: ours, not group/other-writable, not a link.
private_dir() {
  [[ -d $1 && ! -L $1 ]] || return 1
  [[ $(stat -c %u -- "$1") == "$UID" ]] || return 1
  (( (8#$(stat -c %a -- "$1") & 8#022) == 0 ))
}

# Every folder from the home folder down to `dir` is private_dir. Then nobody
# else can swap one of them for a link between this check and chezmoi's read.
private_chain() {
  local d=$1
  [[ $d == "$HOME" || $d == "$HOME"/* ]] || return 1
  while :; do
    private_dir "$d" || return 1
    [[ $d == "$HOME" ]] && return 0
    d=$(dirname -- "$d")
  done
}

# A new folder is added with everything in it: no folder inside may be
# someone else's or writable by others either (links are added as links).
private_tree() {
  [[ -d $1 && ! -L $1 ]] || return 0
  [[ -z $(find "$1" -xdev -type d \( -perm /022 -o ! -uid "$UID" \) -print -quit 2>/dev/null) ]]
}

# New files under the watched folders, NUL-separated end to end: a newline in a
# file name must not split it into other paths. Each one must still lie inside
# a watched folder (its parent resolved, so a symlinked skill stays a symlink).
new_files() {
  local folders=("$@") f parent inside w raw
  # Through a file: a failed chezmoi must fail this function, not look like "no new files".
  raw=$(mktemp) || return 1
  "$cz" unmanaged -0 --path-style=absolute -- "${folders[@]}" > "$raw" || { rm -f "$raw"; return 1; }
  while IFS= read -r -d '' f; do
    # chezmoi itself splits a path at a newline (2.74): such names never reach it.
    if [[ $f =~ [[:cntrl:]] ]]; then printf '  ! %q\n' "$f" >&2; continue; fi
    parent=$(realpath -e -- "$(dirname -- "$f")" 2>/dev/null) || continue
    inside=
    for w in "${folders[@]}"; do
      [[ $parent == "$w" || $parent == "$w"/* ]] && { inside=1; break; }
    done
    if [[ -z $inside ]]; then printf '  ! %q\n' "$f" >&2
    elif ! private_chain "$parent" || ! private_tree "$parent/$(basename -- "$f")"; then
      say "  ! $(printf %q "$f"): a folder on its way is not yours alone, skipped" \
          "  ! $(printf %q "$f"): в папку на пути к нему может писать кто-то ещё, пропущено" >&2
    else printf '%s\0' "$parent/$(basename -- "$f")"; fi
  done < "$raw"
  rm -f "$raw"
}

save() {
  say "Collecting changes…" "Собираю изменения…"
  # A chezmoi `status` pre-hook can refresh generated files before a Send only.
  export DOTFILES_SAVE=1
  # Only the files edited here, and only through folders that are the user's
  # alone: a bare `chezmoi re-add` would read every managed file, also one whose
  # folder somebody else can swap for a link to a private file.
  local line f status edited=()
  # A failed status (chezmoi busy, a broken template) must not read as "nothing to send".
  status=$("$cz" status --exclude=externals,scripts --path-style=absolute) \
    || fail "chezmoi status failed, nothing was sent" "chezmoi status упал, ничего не отправлено"
  while IFS= read -r line; do
    [[ ${line:0:1} == [MA] ]] || continue
    f=${line:3}
    [[ $f == /* && ( -e $f || -L $f ) ]] || continue
    if [[ $f =~ [[:cntrl:]] ]] || ! private_chain "$(dirname -- "$f")" || ! private_tree "$f"; then
      say "  ! $(printf %q "$f"): a folder on its way is not yours alone, skipped" \
          "  ! $(printf %q "$f"): в папку на пути к нему может писать кто-то ещё, пропущено" >&2
      continue
    fi
    edited+=("$f")
  done <<< "$status"
  # Without gitleaks nothing scans an edit to a file already in the repo
  # (chezmoi checks new files only): sending those is the user's explicit choice.
  if ((${#edited[@]})) && ! command -v gitleaks >/dev/null && [[ -z ${DOTFILES_UNSCANNED_OK:-} ]]; then
    printf '  ~ %q\n' "${edited[@]}"
    say "gitleaks is not installed: these edits cannot be scanned for secrets." "gitleaks не установлен: эти правки нельзя проверить на секреты."
    read -rp "$(say "Send them anyway? [y/N] " "Всё равно отправить? [y/N] ")" line || line=
    [[ $line == [yYдД]* ]] || fail "Nothing was sent. Install gitleaks to have edits scanned." "Ничего не отправлено. Поставь gitleaks, чтобы правки проверялись."
  fi
  if ((${#edited[@]})); then
    "$cz" re-add -- "${edited[@]}" || fail "chezmoi re-add failed, nothing was sent" "chezmoi re-add упал, ничего не отправлено"
  fi
  local list
  list=$(mktemp) || fail "no temporary file" "нет временного файла"
  trap 'rm -f "$list"' EXIT
  watched > "$list" || fail "chezmoi data failed, nothing was sent" "chezmoi data упал, ничего не отправлено"
  mapfile -d '' -t folders < "$list"
  if ((${#folders[@]})); then
    new_files "${folders[@]}" > "$list" || fail "chezmoi unmanaged failed, nothing was sent" "chezmoi unmanaged упал, ничего не отправлено"
    mapfile -d '' -t new < "$list"
    if ((${#new[@]})); then
      printf '  + %q\n' "${new[@]}"
      # --secrets=error: chezmoi only warns by default.
      "$cz" add --secrets=error -- "${new[@]}" || fail "chezmoi add refused a file (a secret?), nothing was sent" "chezmoi add отказался добавить файл (секрет?), ничего не отправлено"
    fi
  fi
  if command -v gitleaks >/dev/null && ! gitleaks dir "$src" --no-banner >/dev/null 2>&1; then
    gitleaks dir "$src" --no-banner -v 2>&1 | grep -E 'File:|RuleID:'
    fail "gitleaks found a secret, nothing was sent" "gitleaks нашёл секрет, ничего не отправлено"
  fi
  g add -A
  g diff --cached --quiet || g commit -qm "sync from $(hostname)" || fail "commit failed" "коммит не удался"
  if ! g rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    g push -q -u origin HEAD || fail "push failed" "push не удался"
  else
    g fetch -q origin || fail "GitHub is not reachable; saved here, will send next time" "GitHub недоступен; сохранено тут, отправлю в следующий раз"
    if (($(g rev-list --count 'HEAD..@{u}'))); then
      say "The other machine sent changes too: putting mine on top…" "С другого компа тоже пришли изменения: ставлю свои поверх…"
      if ! g pull -q --rebase; then
        g rebase --abort 2>/dev/null
        fail "Both machines changed the same lines. Saved here, not sent. Press Apply, pick the version, then Send again." \
             "Оба компа изменили одни и те же строки. Сохранено тут, не отправлено. Нажми «Применить», выбери версию, потом снова «Отправить»."
      fi
    fi
    (($(g rev-list --count '@{u}..HEAD'))) && { g push -q || fail "push failed" "push не удался"; }
  fi
  say "Sent ✓" "Отправлено ✓"
}

apply() {
  say "Pulling and applying…" "Скачиваю и применяю…"
  "$cz" update || fail "chezmoi update failed" "chezmoi update не удался"
  say "Applied ✓" "Применено ✓"
}

# chezmoi diff shows what apply would do, so an edit made here reads reversed.
diff_view() {
  case "${1:-}" in
    local)   "$cz" --color=true diff --no-pager --reverse -- "${2/#\~/$HOME}" ;;
    pending) "$cz" --color=true diff --no-pager -- "${2/#\~/$HOME}" ;;
    *)
      # status column 1 = edited here, column 1 blank = only the repo changed it
      local here=() theirs=()
      while IFS= read -r line; do
        if [[ ${line:0:1} != " " ]]; then here+=("$HOME/${line:3}"); else theirs+=("$HOME/${line:3}"); fi
      done < <("$cz" status --exclude=externals,scripts)
      say "=== Not saved on this machine ===" "=== Не сохранено на этом компе ==="
      ((${#here[@]})) && "$cz" --color=true diff --no-pager --reverse -- "${here[@]}"
      if ((${#theirs[@]})); then
        say "=== In the repo, not applied ===" "=== Есть в репо, не применено ==="
        "$cz" --color=true diff --no-pager -- "${theirs[@]}"
      fi
      if g rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 && (($(g rev-list --count 'HEAD..@{u}'))); then
        say "=== Came from the repo, not applied ===" "=== Пришло из репо, не применено ==="
        g -c color.ui=always log --stat -p 'HEAD..@{u}'
      fi ;;
  esac
}

# The repo's version of one file beside the file itself, in a real diff window.
#   compare local|pending PATH
# The repo's version may be a rendered template or a decrypted file: it lives
# in a folder only the user can read, and is removed when the window closes.
compare() {
  local kind=$1 file="${2/#\~/$HOME}" tmp repo tool
  if tool=$(command -v meld) || tool=$(command -v codium) || tool=$(command -v code); then
    tmp=$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/dotfiles-XXXXXX") || exit 1
    trap 'rm -rf "$tmp"' EXIT
    repo="$tmp/$(basename -- "$file") (repo)"
    "$cz" cat -- "$file" > "$repo" 2>/dev/null || : > "$repo"
    case "${tool##*/}" in
      meld) "$tool" "$repo" "$file" ;;
      *) "$tool" --new-window --wait --diff "$repo" "$file" ;;
    esac
    return
  fi
  # No diff tool: the coloured diff in a terminal, in the direction this row reads.
  exec omarchy-launch-floating-terminal-with-presentation \
    "DOTFILES_LANG=$(printf %q "${DOTFILES_LANG:-}") CHEZMOI=$(printf %q "$cz") $(printf '%q ' "$0" diff "$kind" "$2")"
}

case "${1:-}" in
  save) save ;;
  compare) case "${2:-}" in local|pending) compare "$2" "${3:-}" ;; *) compare local "${2:-}" ;; esac ;;
  apply) apply ;;
  diff) shift; diff_view "$@" | less -R ;;
  *) echo "usage: actions.sh save | apply | diff [local|pending PATH] | compare local|pending PATH" >&2; exit 2 ;;
esac
