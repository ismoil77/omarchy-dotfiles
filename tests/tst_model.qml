import QtQuick
import QtTest
import "../Model.js" as Model
import "../Strings.js" as Strings
import "../kit/I18n.js" as I18n

// The same libraries the widget imports, run by Qt's own JavaScript engine:
// a syntax Node accepts but QML does not would fail here.
TestCase {
  name: "Model in the QML engine"

  function test_libraries_load_and_answer() {
    var ru = Model.config({ language: "ru" })
    var s = Model.parse('{"ok":true,"ahead":1,"behind":2,"local":[],"pending":[]}')
    compare(Model.mode(s), "both")
    compare(Model.barLabel(s), "↑1 ↓2")
    compare(Model.stateText(ru, s), "Не отправлено: 1 изменение · из репо: 2 обновления")
    compare(Model.icon(s).codePointAt(0), 0xF063F)
    compare(Model.ago(ru, 1000, 1000 + 7200), "2 ч назад")
    compare(Model.shellQuote("a'b"), "'a'\\''b'")
    verify(Strings.langs.length >= 2)
  }
}
