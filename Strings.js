.pragma library

// Every user-visible word of the widget, per language. {name} placeholders
// are filled by I18n.t; an array is the forms of a noun (see I18n.plural).
// Tests keep the two tables in step.

var en = {
  title: "Dotfiles",
  loading: "Reading chezmoi…",
  errNoChezmoi: "Step 1 of 2: chezmoi is not installed yet",
  errNoSource: "Step 2 of 2: no dotfiles repo is connected yet",
  setupCaption: "First run",
  setupInstall: "chezmoi keeps your config files in a git repo. The button installs it (your password is asked in a terminal).",
  setupConnect: "Paste the address of your dotfiles repo, or start a new one. Nothing on this computer changes until you press Apply.",
  installChezmoi: "Install chezmoi",
  connectRepo: "Connect a repo",
  chipSetup: "set up",
  errBusy: "chezmoi is busy: another chezmoi command is running",
  errInternal: "The reader failed to run (is python3 installed?)",

  stateOk: "Everything is saved",
  stateUp: "Not sent: {up}",
  stateDown: "From the repo: {down}",
  stateBoth: "Not sent: {up} · from the repo: {down}",
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
  kindBlocked: "shared folder: not sent",
  noHistory: "No saves yet",
  more: "{n} more",
  less: "Collapse",

  rowUncommitted: "Prepared, not sent",
  rowAhead: "Saved here, not in the repo",
  rowScripts: "Scripts Apply will run",
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

  chipOk: "saved",
  chipSend: "send",
  chipApply: "apply",
  chipBoth: "send first",
  chipError: "error",
  openHint: "click opens",
  compare: "Compare",
  send: "Send",
  apply: "Apply",
  diff: "Changes"
}

var ru = {
  title: "Dotfiles",
  loading: "Читаю chezmoi…",
  errNoChezmoi: "Шаг 1 из 2: chezmoi ещё не установлен",
  errNoSource: "Шаг 2 из 2: репо с конфигами ещё не подключён",
  setupCaption: "Первый запуск",
  setupInstall: "chezmoi хранит твои конфиги в git-репо. Кнопка установит его (пароль спросят в терминале).",
  setupConnect: "Вставь адрес своего репо с конфигами или начни новый. На этом компе ничего не изменится, пока не нажмёшь «Применить».",
  installChezmoi: "Установить chezmoi",
  connectRepo: "Подключить репо",
  chipSetup: "настроить",
  errBusy: "chezmoi занят: идёт другая команда chezmoi",
  errInternal: "Не удалось запустить чтение (установлен ли python3?)",

  stateOk: "Всё сохранено",
  stateUp: "Не отправлено: {up}",
  stateDown: "Из репо: {down}",
  stateBoth: "Не отправлено: {up} · из репо: {down}",
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
  kindBlocked: "общая папка: не отправится",
  noHistory: "Сохранений ещё нет",
  more: "Ещё {n}",
  less: "Свернуть",

  rowUncommitted: "Подготовлено, не отправлено",
  rowAhead: "Сохранено тут, не в репо",
  rowScripts: "Скрипты, которые запустит «Применить»",
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

  chipOk: "сохранено",
  chipSend: "отправить",
  chipApply: "применить",
  chipBoth: "сначала отправить",
  chipError: "ошибка",
  openHint: "клик открывает",
  compare: "Сравнить",
  send: "Отправить",
  apply: "Применить",
  diff: "Изменения"
}

var langs = ["en", "ru"]
var tables = { en: en, ru: ru }
