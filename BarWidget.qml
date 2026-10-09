import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Due.js" as Due

// Bar icon showing how many tasks are still open, and the host for the
// task list popup. Left click opens the list, right click opens the raw
// tasks file in the editor.
BarWidget {
  id: root
  moduleName: "sendaljpt.taskq"

  readonly property string dataPath: Quickshell.env("HOME") + "/.local/share/omarchy-tasks/tasks.json"
  property var tasks: []
  readonly property int openCount: tasks.filter(function(t) { return !t.done }).length
  // Any Nerd Font glyph or emoji; set with `omarchy bar set sendaljpt.taskq icon <glyph>`.
  readonly property string icon: setting("icon", String.fromCodePoint(0xF0756))

  // Deadline colours from the current theme's colors.toml; red is the
  // shell's own urgent colour. Fallbacks are only used if a theme lacks them.
  property color yellow: "#e5c07b"
  property color green: "#98c379"

  function loadThemeColors(raw) {
    var found = {}
    String(raw || "").split("\n").forEach(function(line) {
      var m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) found[m[1]] = m[2]
    })
    root.yellow = found.yellow || found.color3 || "#e5c07b"
    root.green = found.green || found.color2 || "#98c379"
  }

  // Ticks so countdowns stay current; deadlines are stored as ms timestamps.
  property real now: Date.now()
  readonly property int overdueCount: tasks.filter(function(t) {
    return !t.done && typeof t.due === "number" && t.due < root.now
  }).length

  function load() {
    try {
      var parsed = JSON.parse(String(store.text() || "[]"))
      root.tasks = Array.isArray(parsed) ? parsed : []
    } catch (e) {
      console.warn("tasks: could not parse", dataPath, e)
    }
  }

  function save(next) {
    root.tasks = next
    store.setText(JSON.stringify(next, null, 2) + "\n")
  }

  // "Write report @ tomorrow 17:00" adds the task with a deadline. If the
  // part after @ can't be read, the whole text is kept as the title.
  function addTask(title) {
    var text = String(title || "").trim()
    if (text === "") return
    var task = { id: Date.now(), title: text, done: false, created: new Date().toISOString() }
    var at = text.lastIndexOf(" @ ")
    if (at > 0) {
      var due = Due.parse(text.slice(at + 3), new Date())
      if (typeof due === "number" && !isNaN(due)) {
        task.title = text.slice(0, at).trim()
        task.due = due
      }
    }
    var next = tasks.slice()
    next.push(task)
    save(next)
  }

  // Copies the task with `changes` applied, so fields added later survive.
  function updateTask(id, changes) {
    save(tasks.map(function(t) {
      if (t.id !== id) return t
      var next = {}
      for (var key in t) next[key] = t[key]
      for (var change in changes) next[change] = changes[change]
      return next
    }))
  }

  function toggleTask(id) {
    var task = tasks.find(function(t) { return t.id === id })
    if (task) updateTask(id, { done: !task.done })
  }

  function renameTask(id, title) {
    var text = String(title || "").trim()
    if (text !== "") updateTask(id, { title: text })
  }

  // Accepts anything Due.parse understands; empty clears the deadline.
  // Returns false (and changes nothing) when the text can't be read.
  function setDue(id, text) {
    var due = Due.parse(text, new Date())
    if (due !== null && isNaN(due)) return false
    updateTask(id, { due: due })
    return true
  }

  function removeTask(id) {
    save(tasks.filter(function(t) { return t.id !== id }))
  }

  function clearDone() {
    save(tasks.filter(function(t) { return !t.done }))
  }

  // ---- Popup. Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  FileView {
    id: themeColors
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadThemeColors(text())
    onFileChanged: reload()
  }

  // Theme switches swap the theme directory rather than editing the file,
  // so re-read whenever the shell's own colours change.
  Connections {
    target: Color
    function onForegroundChanged() { themeColors.reload() }
    function onAccentChanged() { themeColors.reload() }
    function onUrgentChanged() { themeColors.reload() }
  }

  FileView {
    id: store
    path: root.dataPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load()
    onFileChanged: reload()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "sendaljpt.taskq"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function add(title: string): void { root.addTask(title) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical
      ? root.icon
      : root.icon + (root.openCount > 0 ? " " + root.openCount : "")
    active: root.overdueCount > 0
    tooltipText: (root.openCount === 0 ? "No open tasks" : root.openCount + " open task" + (root.openCount === 1 ? "" : "s"))
      + (root.overdueCount > 0 ? ", " + root.overdueCount + " overdue" : "")

    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.bar) root.bar.run("xdg-open " + root.bar.shellQuote(root.dataPath)) }
      else root.togglePanel()
    }
  }
}
