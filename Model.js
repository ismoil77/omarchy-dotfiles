.pragma library
.import "kit/I18n.js" as I18n
.import "Strings.js" as Strings

// Pure logic of the Dotfiles widget: reading state.py, counting, texts and
// the terminal commands. No QML here, so tests run it in plain Node.

// A long list shows its first SHORT_LIST rows until it is expanded.
var SHORT_LIST = 5

var ICONS = {
  ok: "\u{F0160}",     // cloud-check
  up: "\u{F0167}",     // cloud-upload
  down: "\u{F0162}",   // cloud-download
  both: "\u{F063F}",   // cloud-sync
  error: "\u{F0164}",  // cloud-off-outline
  loading: "\u{F0160}"
}

var KIND_KEYS = { modified: "kindModified", deleted: "kindDeleted", added: "kindAdded", new: "kindNew" }
var ERROR_KEYS = { nochezmoi: "errNoChezmoi", nosource: "errNoSource", busy: "errBusy", internal: "errInternal" }

// `raw` = { language, locale }; `lang` is what every text function reads.
function config(raw) {
  return { lang: I18n.resolve(raw && raw.language, raw && raw.locale, Strings.langs, { "русский": "ru", english: "en" }) }
}

function tr(cfg, key, params) {
  return I18n.t(Strings.tables, cfg.lang, key, params)
}

function count(cfg, key, n) {
  return I18n.count(Strings.tables, cfg.lang, key, n)
}

function empty() {
  return {
    ok: false, error: "", loaded: false, host: "", remote: "", upstream: false,
    local: [], pending: [], scripts: 0, uncommitted: 0, ahead: 0, behind: 0,
    incoming: [], history: [], fetch: { time: 0, error: "" }
  }
}

function failure(code) {
  return Object.assign(empty(), { loaded: true, error: code || "internal" })
}

function list(v) { return Array.isArray(v) ? v : [] }
function int(v) { var n = Math.floor(Number(v)); return isFinite(n) && n > 0 ? n : 0 }

// state.py prints one JSON object; anything else is no answer (null).
function parse(raw) {
  var data
  try {
    data = JSON.parse(String(raw || "").trim())
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object") return null
  if (!data.ok) return failure(ERROR_KEYS[data.error] ? data.error : "internal")
  var fetch = data.fetch && typeof data.fetch === "object" ? data.fetch : {}
  return {
    ok: true, error: "", loaded: true,
    host: String(data.host || ""),
    remote: String(data.remote || ""),
    upstream: data.upstream === true,
    local: list(data.local), pending: list(data.pending),
    scripts: int(data.scripts), uncommitted: int(data.uncommitted),
    ahead: int(data.ahead), behind: int(data.behind),
    incoming: list(data.incoming), history: list(data.history),
    fetch: { time: int(fetch.time), error: String(fetch.error || "") }
  }
}

// Not in the repo yet: files edited here, files prepared but not committed,
// commits not pushed. Each is a different step of the same "not sent".
function upCount(s) {
  return s.ok ? s.local.length + s.uncommitted + s.ahead : 0
}

// In the repo, not here: commits not pulled, and files pulled but not applied.
function downCount(s) {
  return s.ok ? s.behind + s.pending.length : 0
}

function mode(s) {
  if (!s.loaded) return "loading"
  if (!s.ok) return "error"
  var up = upCount(s), down = downCount(s)
  if (up && down) return "both"
  if (up) return "up"
  if (down) return "down"
  return "ok"
}

function icon(s) { return ICONS[mode(s)] }

// The bar shows only what needs doing: nothing when all is saved.
function barLabel(s) {
  var m = mode(s), up = upCount(s), down = downCount(s)
  if (m === "up") return "↑" + up
  if (m === "down") return "↓" + down
  if (m === "both") return "↑" + up + " ↓" + down
  return ""
}

// What the popup's next step is: the button to stress and to run on Enter.
function recommended(s) {
  var m = mode(s)
  return m === "up" || m === "both" ? "save" : m === "down" ? "apply" : ""
}

function stateText(cfg, s) {
  var m = mode(s)
  if (m === "loading") return tr(cfg, "loading")
  if (m === "error") return tr(cfg, ERROR_KEYS[s.error] || "errInternal")
  var up = count(cfg, "changesN", upCount(s)), down = count(cfg, "updatesN", downCount(s))
  if (m === "both") return tr(cfg, "stateBoth", { up: up, down: down })
  if (m === "up") return tr(cfg, "stateUp", { up: up })
  if (m === "down") return tr(cfg, "stateDown", { down: down })
  return tr(cfg, "stateOk")
}

function hint(cfg, s) {
  var key = { ok: "hintOk", up: "hintUp", down: "hintDown", both: "hintBoth" }[mode(s)]
  return key ? tr(cfg, key) : ""
}

function tooltip(cfg, s) {
  return tr(cfg, "tipBar", { state: stateText(cfg, s) })
}

function kindLabel(cfg, kind) {
  return tr(cfg, KIND_KEYS[kind] || "kindModified")
}

// Seconds since the epoch -> "5 min ago". `now` in seconds too.
function ago(cfg, time, now) {
  var t = int(time)
  if (!t) return ""
  var s = Math.max(0, now - t)
  if (s < 60) return tr(cfg, "justNow")
  if (s < 3600) return tr(cfg, "minAgo", { n: Math.floor(s / 60) })
  if (s < 86400) return tr(cfg, "hourAgo", { n: Math.floor(s / 3600) })
  var days = Math.floor(s / 86400)
  if (days === 1) return tr(cfg, "yesterday")
  return tr(cfg, "daysAgo", { n: count(cfg, "daysN", days) })
}

// "Checked the repo: 3 min ago", or why the last check did not work.
function checkedText(cfg, s, now) {
  var when = ago(cfg, s.fetch.time, now) || tr(cfg, "checkedNever")
  if (s.fetch.error === "auth") return tr(cfg, "fetchAuth")
  if (s.fetch.error === "offline") return tr(cfg, "fetchOffline", { ago: when })
  if (s.fetch.error) return tr(cfg, "fetchFailed", { ago: when })
  return when
}

function commitCells(cfg, c, now) {
  return [count(cfg, "filesN", int(c.files)), ago(cfg, c.time, now)]
}

function visibleRows(rows, all) {
  rows = list(rows)
  return all || rows.length <= SHORT_LIST + 1 ? rows : rows.slice(0, SHORT_LIST)
}

// One hidden row is shown rather than a "1 more" button.
function moreLabel(cfg, rows, all) {
  rows = list(rows)
  if (rows.length <= SHORT_LIST + 1) return ""
  return all ? tr(cfg, "less") : tr(cfg, "more", { n: rows.length - SHORT_LIST })
}

// POSIX single-quoting: any string becomes one shell word.
function shellQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}

// The shell line the terminal runs for a button (args: extra words, e.g. diff local PATH).
function command(script, args, lang, chezmoi) {
  var words = ["DOTFILES_LANG=" + shellQuote(lang)]
  if (chezmoi) words.push("CHEZMOI=" + shellQuote(chezmoi))
  words.push(shellQuote(script))
  for (var i = 0; i < args.length; i++) words.push(shellQuote(args[i]))
  return words.join(" ")
}


// The widest text a column can hold, for TextMetrics: the commits' file counts,
// and every shape an "ago" text can take.
function filesSample(cfg, commits) {
  var best = count(cfg, "filesN", 0)
  commits = list(commits)
  for (var i = 0; i < commits.length; i++) {
    var t = count(cfg, "filesN", int(commits[i].files))
    if (t.length > best.length) best = t
  }
  return best
}

function agoSample(cfg) {
  var all = [tr(cfg, "justNow"), tr(cfg, "minAgo", { n: 59 }), tr(cfg, "hourAgo", { n: 23 }), tr(cfg, "yesterday"),
             tr(cfg, "daysAgo", { n: count(cfg, "daysN", 28) })]
  return all.reduce(function(a, b) { return b.length > a.length ? b : a })
}

// The header's big figure: what needs doing, or a check mark when nothing does.
function headline(s) {
  var m = mode(s)
  if (m === "ok") return "✓"
  if (m === "error" || m === "loading") return "—"
  return barLabel(s).replace(/↑/g, "↑ ").replace(/↓/g, "↓ ")
}

// The header's chip: the next step in one word.
function chipText(cfg, s) {
  var key = { ok: "chipOk", up: "chipSend", down: "chipApply", both: "chipBoth", error: "chipError" }[mode(s)]
  return key ? tr(cfg, key) : ""
}

// "~/x" -> HOME + "/x", for opening a file.
function expandHome(path, home) {
  path = String(path)
  return path === "~" || path.indexOf("~/") === 0 ? home + path.slice(1) : path
}
