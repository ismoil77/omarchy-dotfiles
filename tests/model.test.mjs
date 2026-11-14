import test from "node:test"
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { Model } from "./loader.mjs"

const M = Model()
const en = M.config({ language: "en" })
const ru = M.config({ language: "ru" })
const NOW = 1_800_000_000

const ok = extra => M.parse(JSON.stringify(Object.assign({
  ok: true, error: "", host: "pc", remote: "me/dotfiles", upstream: true, local: [], pending: [],
  scripts: 0, uncommitted: 0, ahead: 0, behind: 0, incoming: [], history: [], fetch: { time: NOW - 120, error: "" }
}, extra)))

test("parse: no answer is null, a failure keeps a known code only", () => {
  assert.equal(M.parse(""), null)
  assert.equal(M.parse("not json"), null)
  assert.equal(M.parse("[1]").ok, false)
  assert.equal(M.parse('{"ok":false,"error":"busy"}').error, "busy")
  assert.equal(M.parse('{"ok":false,"error":"weird"}').error, "internal")
  const s = M.parse('{"ok":true,"ahead":"2","behind":-3,"local":null}')
  assert.equal(s.ahead, 2)
  assert.equal(s.behind, 0)
  assert.deepEqual([...s.local], [])
})

test("mode and bar label follow what needs doing", () => {
  assert.equal(M.mode(M.empty()), "loading")
  assert.equal(M.mode(M.failure("nochezmoi")), "error")
  assert.equal(M.barLabel(M.failure("nochezmoi")), "")

  const clean = ok({})
  assert.equal(M.mode(clean), "ok")
  assert.equal(M.barLabel(clean), "")
  assert.equal(M.recommended(clean), "")

  const up = ok({ local: [{ path: "~/a", kind: "modified" }], uncommitted: 1, ahead: 1 })
  assert.equal(M.mode(up), "up")
  assert.equal(M.barLabel(up), "↑3")
  assert.equal(M.recommended(up), "save")

  const down = ok({ behind: 2, pending: [{ path: "~/b", kind: "added" }] })
  assert.equal(M.mode(down), "down")
  assert.equal(M.barLabel(down), "↓3")
  assert.equal(M.recommended(down), "apply")

  const both = ok({ ahead: 1, behind: 1 })
  assert.equal(M.mode(both), "both")
  assert.equal(M.barLabel(both), "↑1 ↓1")
  assert.equal(M.recommended(both), "save")
})

test("every mode has its own icon", () => {
  const icons = [ok({}), ok({ ahead: 1 }), ok({ behind: 1 }), ok({ ahead: 1, behind: 1 }), M.failure("busy")].map(M.icon)
  assert.equal(new Set(icons).size, icons.length)
})

test("state texts in both languages", () => {
  assert.equal(M.stateText(en, ok({})), "Everything is saved")
  assert.equal(M.stateText(ru, ok({ ahead: 3 })), "Не отправлено: 3 изменения")
  assert.equal(M.stateText(ru, ok({ behind: 5 })), "Из репо: 5 обновлений")
  assert.equal(M.stateText(en, ok({ ahead: 1, behind: 1 })), "Not sent: 1 change · from the repo: 1 update")
  assert.equal(M.stateText(ru, M.failure("nosource")), "У chezmoi ещё нет репо: сделай chezmoi init")
})

test("ago", () => {
  assert.equal(M.ago(en, 0, NOW), "")
  assert.equal(M.ago(en, NOW - 10, NOW), "just now")
  assert.equal(M.ago(ru, NOW - 5 * 60, NOW), "5 мин назад")
  assert.equal(M.ago(en, NOW - 3 * 3600, NOW), "3 h ago")
  assert.equal(M.ago(ru, NOW - 30 * 3600, NOW), "вчера")
  assert.equal(M.ago(ru, NOW - 3 * 86400, NOW), "3 дня назад")
  assert.equal(M.ago(en, NOW + 50, NOW), "just now")
})

test("checked text tells why the repo could not be asked", () => {
  assert.equal(M.checkedText(en, ok({}), NOW), "2 min ago")
  assert.equal(M.checkedText(en, ok({ fetch: { time: 0, error: "" } }), NOW), "not yet")
  assert.equal(M.checkedText(ru, ok({ fetch: { time: NOW - 120, error: "offline" } }), NOW), "2 мин назад, сейчас нет сети")
  assert.equal(M.checkedText(en, ok({ fetch: { time: 0, error: "auth" } }), NOW), "no access: run gh auth login")
})

test("lists: one hidden row is shown, more are behind a button", () => {
  const rows = n => Array.from({ length: n }, (_, i) => i)
  assert.equal(M.visibleRows(rows(6), false).length, 6)
  assert.equal(M.moreLabel(en, rows(6), false), "")
  assert.equal(M.visibleRows(rows(9), false).length, 5)
  assert.equal(M.moreLabel(ru, rows(9), false), "Ещё 4")
  assert.equal(M.visibleRows(rows(9), true).length, 9)
  assert.equal(M.moreLabel(en, rows(9), true), "Collapse")
})

test("commit cells", () => {
  assert.deepEqual([...M.commitCells(ru, { files: 2, time: NOW - 60 }, NOW)], ["2 файла", "1 мин назад"])
})

test("the terminal command survives quotes and spaces", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dot it's "))
  const script = path.join(dir, "actions.sh")
  fs.writeFileSync(script, '#!/bin/bash\nprintf "%s\\n" "$DOTFILES_LANG" "$CHEZMOI" "$@"\n', { mode: 0o755 })
  const line = M.command(script, ["diff", "local", "~/x y'z"], "ru", "/opt/c z/chezmoi")
  // The launcher hands the line to bash -c, as the widget's terminal does.
  const out = execFileSync("bash", ["-c", line]).toString()
  fs.rmSync(dir, { recursive: true })
  assert.deepEqual(out.trimEnd().split("\n"), ["ru", "/opt/c z/chezmoi", "diff", "local", "~/x y'z"])
  assert.equal(M.shellQuote("a'b"), "'a'\\''b'")
})

test("column samples are the widest texts", () => {
  assert.equal(M.filesSample(ru, [{ files: 2 }, { files: 448 }]), "448 файлов")
  assert.equal(M.filesSample(en, []), "0 files")
  assert.equal(M.agoSample(ru), "28 дней назад")
  assert.equal(M.agoSample(en), "28 days ago")
})

test("header figure, chip and home paths", () => {
  assert.equal(M.headline(ok({})), "✓")
  assert.equal(M.headline(ok({ ahead: 2, behind: 1 })), "↑ 2 ↓ 1")
  assert.equal(M.headline(M.failure("busy")), "—")
  assert.equal(M.chipText(ru, ok({ behind: 1 })), "применить")
  assert.equal(M.chipText(en, ok({})), "saved")
  assert.equal(M.expandHome("~/.config/x", "/home/me"), "/home/me/.config/x")
  assert.equal(M.expandHome("/etc/x", "/home/me"), "/etc/x")
})

test("a blocked file is listed but not counted as to send", () => {
  const s = ok({ local: [{ path: "~/a", kind: "modified" }, { path: "~/shared/b", kind: "blocked" }] })
  assert.equal(M.barLabel(s), "↑1")
  assert.equal(M.kindLabel(ru, "blocked"), "общая папка: не отправится")
  assert.equal(M.mode(ok({ local: [{ path: "~/shared/b", kind: "blocked" }] })), "ok")
})
