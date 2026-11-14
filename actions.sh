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
g() { git -C "$src" "$@"; }

# Folders under dotfiles.watch in chezmoi data that exist on this machine.
watched() {
  "$cz" data --format=json | python3 -I -c '
import json, os, sys
for p in (json.load(sys.stdin).get("dotfiles") or {}).get("watch") or []:
    p = os.path.expanduser(str(p))
    if os.path.isdir(p): print(p)'
}

save() {
  say "Collecting changes…" "Собираю изменения…"
  "$cz" re-add || fail "chezmoi re-add failed, nothing was sent" "chezmoi re-add упал, ничего не отправлено"
  mapfile -t folders < <(watched)
  if ((${#folders[@]})); then
    mapfile -t new < <("$cz" unmanaged --path-style=absolute "${folders[@]}")
    if ((${#new[@]})); then
      printf '  + %s\n' "${new[@]}"
      "$cz" add "${new[@]}" || fail "chezmoi add refused a file (a secret?), nothing was sent" "chezmoi add отказался добавить файл (секрет?), ничего не отправлено"
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
