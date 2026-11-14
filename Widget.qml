import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "kit" as Kit
import "Model.js" as Model

// Dotfiles widget: whether this machine's chezmoi configs are in the repo,
// and whether the repo has something this machine has not applied.
//
//   bar          cloud icon; ↑N not sent, ↓N to apply, nothing when all is saved
//   left click   open/close the popup
//   right click  check the repo again
//   popup        what is not sent, what came from the repo, the last saves;
//                Send (s), Apply (a), Changes (d), r checks again, Enter runs
//                the stressed button; a file row opens its change
// Buttons run actions.sh in a floating terminal so chezmoi can ask questions.
Panel {
  id: root
  moduleName: "ismoil.dotfiles"
  ipcTarget: "ismoil.dotfiles"
  manageIpc: false

  readonly property int pollSeconds: Math.max(30, Number(setting("interval", 120)) || 120)
  readonly property int fetchMinutes: Math.max(1, Number(setting("fetchMinutes", 10)) || 10)
  readonly property string chezmoi: String(setting("chezmoi", "")).trim()
  readonly property var cfg: Model.config({ language: setting("language", "auto"), locale: Qt.locale().name })

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property string script: localPath(Qt.resolvedUrl("state.py"))
  readonly property string actions: localPath(Qt.resolvedUrl("actions.sh"))

  property var info: Model.empty()
  // Seconds since the epoch, ticking once a minute for the "5 min ago" texts.
  property real now: Date.now() / 1000
  property bool allLocal: false
  property bool allPending: false
  // When the repo was last asked (ms); 0 makes the first run fetch.
  property real fetchedAt: 0
  // A button's terminal may change things for a while: check often until then.
  property real watchUntil: 0
  // Asked while state.py was running: one more run follows it, fetching if asked to.
  property bool rerun: false
  property bool rerunFetch: false
  property bool answered: false

  readonly property string mode: Model.mode(info)
  readonly property string next: Model.recommended(info)
  readonly property color stateColor: skin.levelText(kitLevel)

  function tr(key, params) { return Model.tr(cfg, key, params) }

  // file:///a%20b/x.py -> /a b/x.py
  function localPath(url) {
    return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
  }

  Kit.ThemePalette { id: themePalette }
  Kit.Look {
    id: skin
    textSize: String(root.setting("textSize", "Normal"))
    animations: root.setting("animations", true) !== false
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    themeColors: themePalette.colors
  }
  // ok -> the theme's green, something to do -> its yellow, an error -> red.
  readonly property string kitLevel: mode === "error" ? "bad" : mode === "ok" || mode === "loading" ? "good" : "warn"

  TextMetrics { id: kindMetrics; font.family: skin.fontFamily; font.pixelSize: skin.small; text: root.tr("kindModified") + "  " }
  TextMetrics { id: filesMetrics; font.family: skin.fontFamily; font.pixelSize: skin.small; text: Model.filesSample(root.cfg, root.info.history.concat(root.info.incoming)) + "  " }
  TextMetrics { id: agoMetrics; font.family: skin.fontFamily; font.pixelSize: skin.small; text: Model.agoSample(root.cfg) }

  function refresh(withFetch) {
    if (stateProc.running) {
      rerun = true
      rerunFetch = rerunFetch || withFetch
      return
    }
    var command = ["python3", "-I", script]
    if (withFetch) {
      command.push("--fetch")
      fetchedAt = Date.now()
    }
    if (chezmoi !== "") command.push("--chezmoi", chezmoi)
    answered = false
    stateProc.command = command
    stateProc.running = true
  }

  function fetchDue() {
    return Date.now() - fetchedAt >= fetchMinutes * 60000
  }

  // `raw` is what state.py printed; no usable answer is an error in its own right.
  function applyState(raw) {
    answered = true
    var next = Model.parse(raw) || Model.failure("internal")
    // A busy chezmoi (another command holds its lock) is worth waiting out.
    if (next.error === "busy" && info.ok) return
    info = next
    now = Date.now() / 1000
  }

  // args: ["save"], ["apply"], ["diff"], ["diff", "local", path]
  function runAction(args) {
    close()
    if (!bar) return
    bar.run("omarchy-launch-floating-terminal-with-presentation " + Model.shellQuote(Model.command(actions, args, cfg.lang, chezmoi)))
    watchUntil = Date.now() + 180000
  }

  function runNext() {
    if (next !== "") runAction([next])
    else refresh(true)
  }

  function showFile(row, pending) {
    if (row.kind === "new") return
    runAction(["diff", pending ? "pending" : "local", row.path])
  }

  IpcHandler {
    target: "ismoil.dotfiles"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh(true) }
    function send(): void { root.runAction(["save"]) }
    function apply(): void { root.runAction(["apply"]) }
  }

  Process {
    id: stateProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyState(text) }
    // python3 missing or killed: nothing was printed. The output can still be
    // on its way when the exit is reported, so the verdict waits a moment.
    onExited: function(code, status) { silence.restart() }
    onRunningChanged: {
      if (running || !root.rerun) return
      var withFetch = root.rerunFetch
      root.rerun = false
      root.rerunFetch = false
      root.refresh(withFetch)
    }
  }

  Timer {
    id: silence
    interval: 500
    onTriggered: if (!root.answered && !stateProc.running) root.applyState("")
  }

  // Local checks are cheap (chezmoi status, git); the repo is asked every fetchMinutes.
  Timer {
    interval: Date.now() < root.watchUntil ? 3000 : root.pollSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(root.fetchDue())
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.now = Date.now() / 1000
  }

  onOpenedChanged: {
    if (opened) {
      now = Date.now() / 1000
      // Opening asks the repo unless it was asked a moment ago.
      Qt.callLater(function() { root.refresh(Date.now() - root.fetchedAt > 60000) })
    } else {
      allLocal = false
      allPending = false
      scroller.contentY = 0
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  TextMetrics {
    id: barLabelMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    text: button.labelText
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Omarchy 4.5: `text` is a single icon glyph; the counts go in `labelText`.
    text: Model.icon(root.info)
    labelText: root.vertical ? "" : Model.barLabel(root.info)
    slotSize: root.vertical || labelText === "" ? Style.bar.iconSlot : Math.ceil(button.canvasSize + barLabelMetrics.width + Style.space(4)) + Style.space(14)
    tooltipText: root.opened ? "" : Model.tooltip(root.cfg, root.info)
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh(true)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Math.round(Style.space(400) * skin.textScale))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + skin.bottomPad)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.runNext()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r") root.refresh(true)
        else if (t === "s") root.runAction(["save"])
        else if (t === "a") root.runAction(["apply"])
        else if (t === "d") root.runAction(["diff"])
      }

      // A long file list or large text can outgrow the screen: it scrolls.
      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + skin.bottomPad
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
          id: column
          width: scroller.width
          spacing: Style.space(12)

          // ---------- Hero: state icon · title, state and what to do ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Rectangle {
              id: heroIcon
              width: Math.round(skin.hero * 1.7)
              height: width
              radius: skin.radius
              color: Util.alpha(skin.levelFill(root.kitLevel), 0.16)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              Behavior on color { ColorAnimation { duration: skin.fade } }

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: Model.icon(root.info)
                color: root.stateColor
                font.family: skin.fontFamily
                font.pixelSize: skin.hero
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: Model.stateText(root.cfg, root.info)
                color: skin.ink
                font.family: skin.fontFamily
                font.pixelSize: skin.strong
                font.bold: true
                wrapMode: Text.WordWrap
                width: parent.width
              }

              Text {
                visible: text !== ""
                textFormat: Text.PlainText
                text: Model.hint(root.cfg, root.info)
                color: skin.dim
                font.family: skin.fontFamily
                font.pixelSize: skin.small
                wrapMode: Text.WordWrap
                width: parent.width
              }
            }
          }

          // ---------- Not sent: files edited or new here ----------
          Kit.Card {
            id: localList
            look: skin
            visible: root.info.local.length > 0
            width: parent.width
            spacing: Style.space(3)

            PanelSectionHeader {
              text: root.tr("sectionLocal").toUpperCase()
              foreground: skin.ink
              fontFamily: skin.fontFamily
              fontSize: skin.small
              color: skin.dim
            }

            Repeater {
              model: Model.visibleRows(root.info.local, root.allLocal)

              delegate: Kit.StatRow {
                required property var modelData
                width: localList.width - localList.padding * 2
                look: skin
                name: modelData.path
                cells: [Model.kindLabel(root.cfg, modelData.kind)]
                cellWidths: [kindMetrics.width]
                dimCells: [true]
                share: 0
                clickable: modelData.kind !== "new"
                onClicked: root.showFile(modelData, false)
              }
            }

            Kit.MoreButton {
              look: skin
              text: Model.moreLabel(root.cfg, root.info.local, root.allLocal)
              onClicked: root.allLocal = !root.allLocal
            }
          }

          Kit.Card {
            visible: root.info.uncommitted > 0 || root.info.ahead > 0
            width: parent.width
            look: skin
            spacing: Style.spacing.labelGap

            Kit.InfoPair {
              look: skin
              visible: root.info.uncommitted > 0
              label: root.tr("rowUncommitted")
              value: Model.count(root.cfg, "filesN", root.info.uncommitted)
            }
            Kit.InfoPair {
              look: skin
              visible: root.info.ahead > 0
              label: root.tr("rowAhead")
              value: Model.count(root.cfg, "savesN", root.info.ahead)
            }
          }

          // ---------- From the repo: commits not pulled ----------
          Kit.Card {
            id: incomingList
            look: skin
            visible: root.info.incoming.length > 0
            width: parent.width
            spacing: Style.space(3)

            PanelSectionHeader {
              text: root.tr("sectionIncoming").toUpperCase()
              foreground: skin.ink
              fontFamily: skin.fontFamily
              fontSize: skin.small
              color: skin.dim
            }

            Repeater {
              model: root.info.incoming

              delegate: Kit.StatRow {
                required property var modelData
                width: incomingList.width - incomingList.padding * 2
                look: skin
                name: modelData.subject
                cells: Model.commitCells(root.cfg, modelData, root.now)
                cellWidths: [filesMetrics.width, agoMetrics.width]
                dimCells: [true, true]
                share: 0
              }
            }
          }

          // ---------- Pulled, not applied ----------
          Kit.Card {
            id: pendingList
            look: skin
            visible: root.info.pending.length > 0
            width: parent.width
            spacing: Style.space(3)

            PanelSectionHeader {
              text: root.tr("sectionPending").toUpperCase()
              foreground: skin.ink
              fontFamily: skin.fontFamily
              fontSize: skin.small
              color: skin.dim
            }

            Repeater {
              model: Model.visibleRows(root.info.pending, root.allPending)

              delegate: Kit.StatRow {
                required property var modelData
                width: pendingList.width - pendingList.padding * 2
                look: skin
                name: modelData.path
                cells: [Model.kindLabel(root.cfg, modelData.kind)]
                cellWidths: [kindMetrics.width]
                dimCells: [true]
                share: 0
                clickable: true
                onClicked: root.showFile(modelData, true)
              }
            }

            Kit.MoreButton {
              look: skin
              text: Model.moreLabel(root.cfg, root.info.pending, root.allPending)
              onClicked: root.allPending = !root.allPending
            }
          }

          // ---------- Last saves ----------

          Kit.Card {
            id: historyList
            look: skin
            visible: root.info.ok
            width: parent.width
            spacing: Style.space(3)

            PanelSectionHeader {
              text: root.tr("sectionHistory").toUpperCase()
              foreground: skin.ink
              fontFamily: skin.fontFamily
              fontSize: skin.small
              color: skin.dim
            }

            Text {
              visible: root.info.history.length === 0
              textFormat: Text.PlainText
              text: root.tr("noHistory")
              color: skin.dim
              font.family: skin.fontFamily
              font.pixelSize: skin.small
            }

            Repeater {
              model: root.info.history

              delegate: Kit.StatRow {
                required property var modelData
                width: historyList.width - historyList.padding * 2
                look: skin
                name: modelData.subject
                cells: Model.commitCells(root.cfg, modelData, root.now)
                cellWidths: [filesMetrics.width, agoMetrics.width]
                dimCells: [true, true]
                share: 0
              }
            }
          }

          Kit.Card {
            visible: root.info.ok
            width: parent.width
            look: skin
            spacing: Style.spacing.labelGap

            Kit.InfoPair {
              look: skin
              label: root.tr("rowRepo")
              value: root.info.remote || root.tr("rowRepoNone")
            }
            Kit.InfoPair {
              look: skin
              label: root.tr("rowChecked")
              value: Model.checkedText(root.cfg, root.info, root.now)
              valueColor: root.info.fetch.error ? skin.urgentText : skin.ink
            }
            Kit.InfoPair {
              look: skin
              visible: root.info.scripts > 0
              label: root.tr("rowScripts")
              value: String(root.info.scripts)
            }
          }

          // ---------- Actions ----------

          Row {
            id: actionRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing * 2) / 3
            readonly property real buttonHeight: Math.max(sendButton.implicitHeight, applyButton.implicitHeight, diffButton.implicitHeight)

            Button {
              id: sendButton
              width: actionRow.cellWidth
              height: actionRow.buttonHeight
              iconText: "\u{F0167}"
              iconSize: skin.strong
              text: root.tr("send")
              tooltipText: root.tr("sendTip")
              selected: root.next === "save"
              fontSize: skin.small
              foreground: skin.ink
              fontFamily: skin.fontFamily
              bordered: true
              onClicked: root.runAction(["save"])
            }

            Button {
              id: applyButton
              width: actionRow.cellWidth
              height: actionRow.buttonHeight
              iconText: "\u{F0162}"
              iconSize: skin.strong
              text: root.tr("apply")
              tooltipText: root.tr("applyTip")
              selected: root.next === "apply"
              fontSize: skin.small
              foreground: skin.ink
              fontFamily: skin.fontFamily
              bordered: true
              onClicked: root.runAction(["apply"])
            }

            Button {
              id: diffButton
              width: actionRow.cellWidth
              height: actionRow.buttonHeight
              iconText: "\u{F0219}"
              iconSize: skin.strong
              text: root.tr("diff")
              tooltipText: root.tr("diffTip")
              fontSize: skin.small
              foreground: skin.ink
              fontFamily: skin.fontFamily
              bordered: true
              onClicked: root.runAction(["diff"])
            }
          }
        }
      }
    }
  }
}
