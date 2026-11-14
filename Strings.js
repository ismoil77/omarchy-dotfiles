.pragma library

// Every user-visible word of the widget, per language. {name} placeholders
// are filled by I18n.t; an array is the forms of a noun (see I18n.plural).
// Tests keep the two tables in step.

var en = {
  title: "Dotfiles",
  loading: "Reading chezmoi…",
  errNoChezmoi: "chezmoi is not installed",
  errNoSource: "chezmoi has no repo yet: run chezmoi init",
  errBusy: "chezmoi is busy: another chezmoi command is running",
  errInternal: "The reader failed to run (is python3 installed?)",

  stateOk: "Everything is saved",
  stateUp: "Not sent: {up}",
  stateDown: "From the repo: {down}",
  stateBoth: "Not sent: {up} · from the repo: {down}",
  hintOk: "Nothing to do",
  hintUp: "Press Send to put them in the repo",
  hintDown: "Press Apply to get them on this machine",
  hintBoth: "Send first, then Apply",
  tipBar: "Dotfiles: {state}",

  changesN: ["change", "changes"],
  updatesN: ["update", "updates"],
  filesN: ["file", "files"],
  savesN: ["save", "saves"],
  daysN: ["day", "days"],

  sectionLocal: "Not sent",
  sectionIncoming: "From the repo",
  sectionPending: "In the repo, not applied here",
  sectionHistory: "Last saves",
  kindModified: "changed",
  kindDeleted: "deleted",
  kindAdded: "added",
  kindNew: "new",
  rowTip: "Show the change",
  noHistory: "No saves yet",
  more: "{n} more",
  less: "Collapse",

  rowUncommitted: "Prepared, not sent",
  rowAhead: "Saved here, not in the repo",
  rowScripts: "Scripts Apply will run",
  rowRepo: "Repo",
  rowRepoNone: "not connected",
  rowChecked: "Checked the repo",
  checkedNever: "not yet",
  fetchOffline: "{ago}, no network now",
  fetchAuth: "no access: run gh auth login",
  fetchFailed: "{ago}, the last check failed",

  justNow: "just now",
  minAgo: "{n} min ago",
  hourAgo: "{n} h ago",
  yesterday: "yesterday",
  daysAgo: "{n} ago",

  send: "Send",
  sendTip: "Save edits and new files to the repo · S",
  apply: "Apply",
  applyTip: "Pull the repo and apply it here · A",
  diff: "Changes",
  diffTip: "What differs, in a terminal · D"
}

var ru = {
  title: "Dotfiles",
  loading: "Читаю chezmoi…",
  errNoChezmoi: "chezmoi не установлен",
  errNoSource: "У chezmoi ещё нет репо: сделай chezmoi init",
  errBusy: "chezmoi занят: идёт другая команда chezmoi",
  errInternal: "Не удалось запустить чтение (установлен ли python3?)",

  stateOk: "Всё сохранено",
  stateUp: "Не отправлено: {up}",
  stateDown: "Из репо: {down}",
  stateBoth: "Не отправлено: {up} · из репо: {down}",
  hintOk: "Делать ничего не нужно",
  hintUp: "Нажми «Отправить», чтобы они ушли в репо",
  hintDown: "Нажми «Применить», чтобы забрать их на этот комп",
  hintBoth: "Сначала «Отправить», потом «Применить»",
  tipBar: "Dotfiles: {state}",

  changesN: ["изменение", "изменения", "изменений"],
  updatesN: ["обновление", "обновления", "обновлений"],
  filesN: ["файл", "файла", "файлов"],
  savesN: ["сохранение", "сохранения", "сохранений"],
  daysN: ["день", "дня", "дней"],

  sectionLocal: "Не отправлено",
  sectionIncoming: "Из репо",
  sectionPending: "Есть в репо, не применено тут",
  sectionHistory: "Последние сохранения",
  kindModified: "изменён",
  kindDeleted: "удалён",
  kindAdded: "добавлен",
  kindNew: "новый",
  rowTip: "Показать изменение",
  noHistory: "Сохранений ещё нет",
  more: "Ещё {n}",
  less: "Свернуть",

  rowUncommitted: "Подготовлено, не отправлено",
  rowAhead: "Сохранено тут, не в репо",
  rowScripts: "Скрипты, которые запустит «Применить»",
  rowRepo: "Репо",
  rowRepoNone: "не подключён",
  rowChecked: "Проверено в репо",
  checkedNever: "ещё нет",
  fetchOffline: "{ago}, сейчас нет сети",
  fetchAuth: "нет доступа: сделай gh auth login",
  fetchFailed: "{ago}, последняя проверка не удалась",

  justNow: "только что",
  minAgo: "{n} мин назад",
  hourAgo: "{n} ч назад",
  yesterday: "вчера",
  daysAgo: "{n} назад",

  send: "Отправить",
  sendTip: "Сохранить правки и новые файлы в репо · S",
  apply: "Применить",
  applyTip: "Скачать репо и применить на этом компе · A",
  diff: "Изменения",
  diffTip: "Что отличается, в терминале · D"
}

var langs = ["en", "ru"]
var tables = { en: en, ru: ru }
