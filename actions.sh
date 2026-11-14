#!/usr/bin/env bash
# What the Dotfiles widget's buttons run, in a terminal so chezmoi can ask.
#   actions.sh save             re-add edits, add new files in dotfiles.watch, commit, push
#   actions.sh apply            chezmoi update: pull the repo and apply it here
#   actions.sh diff             what is not saved here, then what came from the repo
#   actions.sh diff local PATH  one file: the edit made on this machine
#   actions.sh diff pending PATH  one file: what apply would write
#   actions.sh compare PATH     the repo's version beside the file on disk, in
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
# The repo is git's working directory, not an argument: any local account can
# read a process's command line.
g() { (cd "$src" && git "$@"); }

# Folders under dotfiles.watch in chezmoi data that exist on this machine.
watched() {
  "$cz" data --format=json | python3 -I -c '
import json, os, sys
for p in (json.load(sys.stdin).get("dotfiles") or {}).get("watch") or []:
    p = os.path.expanduser(str(p))
    if os.path.isdir(p): print(os.path.realpath(p), end="\0")'
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
  local folders=("$@") f parent inside w
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
  done < <("$cz" unmanaged -0 --path-style=absolute -- "${folders[@]}")
}

save() {
  say "Collecting changes…" "Собираю изменения…"
  "$cz" re-add || fail "chezmoi re-add failed, nothing was sent" "chezmoi re-add упал, ничего не отправлено"
  mapfile -d '' -t folders < <(watched)
  if ((${#folders[@]})); then
    mapfile -d '' -t new < <(new_files "${folders[@]}")
    if ((${#new[@]})); then
      printf '  + %q\n' "${new[@]}"
      # --secrets=error: chezmoi only warns by default.
      "$cz" add --secrets=error -- "${new[@]}" || fail "chezmoi add refused a file (a secret?), nothing was sent" "chezmoi add отказался добавить файл (секрет?), ничего не отправлено"
    fi
  fi
  # Edits to files already in the repo are scanned by gitleaks only.
  command -v gitleaks >/dev/null || say "Note: gitleaks is not installed, edits to files already in the repo are not scanned for secrets" \
                                        "Внимание: gitleaks не установлен, правки уже сохранённых файлов не проверяются на секреты"
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
compare() {
  local file="${1/#\~/$HOME}" tmp repo tool
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-XXXXXX") || exit 1
  repo="$tmp/$(basename "$file") (repo)"
  "$cz" cat -- "$file" > "$repo" 2>/dev/null || : > "$repo"
  if tool=$(command -v meld); then exec "$tool" "$repo" "$file"; fi
  if tool=$(command -v codium || command -v code); then exec "$tool" --new-window --diff "$repo" "$file"; fi
  exec omarchy-launch-floating-terminal-with-presentation "DOTFILES_LANG=${DOTFILES_LANG:-} $(printf '%q ' "$0" diff local "$1")"
}

case "${1:-}" in
  save) save ;;
  compare) compare "${2:-}" ;;
  apply) apply ;;
  diff) shift; diff_view "$@" | less -R ;;
  *) echo "usage: actions.sh save | apply | diff [local|pending PATH] | compare PATH" >&2; exit 2 ;;
esac
