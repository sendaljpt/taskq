import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Due.js" as Due

// The task list popup. BarWidget.qml owns the data and hands this panel
// the button to anchor against; every edit goes back through hostWidget.
Panel {
  id: root
  moduleName: "sendaljpt.taskq"
  ipcTarget: "sendaljpt.taskq"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var tasks: hostWidget ? hostWidget.tasks : []
  readonly property int openCount: hostWidget ? hostWidget.openCount : 0
  readonly property int doneCount: tasks.length - openCount
  readonly property real now: hostWidget ? hostWidget.now : Date.now()

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property bool groupByGroup: false

  // Open tasks soonest deadline first (no deadline last), then completed ones.
  readonly property var sortedTasks: {
    var open = tasks.filter(function(t) { return !t.done })
    var done = tasks.filter(function(t) { return t.done })
    open.sort(function(a, b) {
      var da = typeof a.due === "number" ? a.due : Infinity
      var db = typeof b.due === "number" ? b.due : Infinity
      return da === db ? 0 : (da < db ? -1 : 1)
    })
    if (root.groupByGroup) {
      var grouped = open.concat(done)
      grouped.sort(function(a, b) {
        var ga = String(a.group || "").trim()
        var gb = String(b.group || "").trim()
        var gaLower = ga.toLowerCase()
        var gbLower = gb.toLowerCase()
        if (gaLower !== gbLower) {
          if (gaLower === "") return -1
          if (gbLower === "") return 1
          return gaLower < gbLower ? -1 : 1
        }
        if (ga !== gb) return ga < gb ? -1 : 1
        if (!!a.done !== !!b.done) return a.done ? 1 : -1
        var da = typeof a.due === "number" ? a.due : Infinity
        var db = typeof b.due === "number" ? b.due : Infinity
        return da === db ? 0 : (da < db ? -1 : 1)
      })
      return grouped
    }
    return open.concat(done)
  }

  // The task being edited and what is being edited: "title" or "due".
  property var editingId: null
  property string editMode: "title"

  function startEditing(id, mode) {
    root.editMode = mode || "title"
    root.editingId = id
  }

  function finishEditing(id, text) {
    if (!root.hostWidget) return root.cancelEditing()
    if (root.editMode === "due") {
      // Unreadable input keeps the field open; the preview says why.
      if (!root.hostWidget.setDue(id, text)) return
    } else if (root.editMode === "group") {
      root.hostWidget.setGroup(id, text)
    } else {
      root.hostWidget.renameTask(id, text)
    }
    root.cancelEditing()
  }

  function cancelEditing() {
    root.editingId = null
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  // Red under 2 hours (and overdue), yellow under 6 hours, green beyond.
  function dueColor(due) {
    var state = Due.status(due, root.now)
    if (state === "overdue" || state === "urgent") return Color.urgent
    if (state === "warning") return root.hostWidget ? root.hostWidget.yellow : Color.accent
    return root.hostWidget ? root.hostWidget.green : Color.muted
  }

  // Live read-out under the deadline field while typing.
  function duePreview(text) {
    var due = Due.parse(text, new Date(root.now))
    if (due === null) return "Empty clears the deadline · Enter to save"
    if (isNaN(due)) return "Not understood · try 17:00, +2h, tomorrow 9am, fri, 12/10"
    return "→ " + Due.describe(due) + " (" + Due.countdown(due, root.now) + ")"
  }

  function open() {
    root.controller.show()
    Qt.callLater(function() { if (root.editingId === null) input.forceActiveFocus() })
  }

  function close() {
    root.editingId = null
    root.controller.hide()
  }

  function toggle() { root.opened ? root.close() : root.open() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: input
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(header.implicitHeight + Style.space(8) + column.implicitHeight, Style.space(560))

    Item {
      anchors.fill: parent

      Column {
        id: header
        width: parent.width
        spacing: Style.space(8)

        // ---- Header
        Item {
          width: parent.width
          height: title.implicitHeight

          Text {
            id: title
            text: "TaskQ"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            id: groupToggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.groupByGroup ? "Group: on" : "Group"
            color: groupToggleMouse.containsMouse ? Color.accent : (root.groupByGroup ? Color.accent : Color.muted)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.underline: groupToggleMouse.containsMouse

            MouseArea {
              id: groupToggleMouse
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.groupByGroup = !root.groupByGroup
            }
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: groupToggle.implicitWidth + Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.tasks.length === 0 ? "" : root.doneCount + " / " + root.tasks.length + " done"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- New task. "title @ deadline" sets a deadline in one go.
        TextField {
          id: input
          width: parent.width
          placeholderText: "Add a task… (add  @ 17:00  for a deadline)"
          foreground: root.fg
          onAccepted: {
            if (root.hostWidget) root.hostWidget.addTask(text)
            text = ""
          }
          Keys.onEscapePressed: root.close()
        }
      }

      Flickable {
        anchors.top: header.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: parent.width
          spacing: Style.space(8)

          Text {
            visible: root.tasks.length === 0
            width: parent.width
            topPadding: Style.space(6)
            bottomPadding: Style.space(6)
            horizontalAlignment: Text.AlignHCenter
            text: "Nothing to do. Enjoy your day!"
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // ---- Task rows
          Repeater {
            model: root.sortedTasks

            Rectangle {
              id: row
              required property var modelData
              required property int index
              readonly property bool editing: root.editingId === modelData.id
              readonly property bool hasDue: typeof modelData.due === "number"
              readonly property bool hovered: rowMouse.containsMouse || dueMouse.containsMouse
                || groupMouse.containsMouse || editMouse.containsMouse || removeMouse.containsMouse
              readonly property string groupName: String(modelData.group || "").trim()
              readonly property bool showGroupHeading: root.groupByGroup
                && (index === 0 || String(root.sortedTasks[index - 1].group || "").trim() !== row.groupName)
              readonly property int groupHeaderHeight: showGroupHeading ? Style.font.bodySmall + Style.space(6) : 0

              width: column.width
              height: row.groupHeaderHeight + (row.editing
                ? editColumn.implicitHeight + Style.space(6)
                : Math.max(Style.space(28), label.implicitHeight + Style.space(8)))
              radius: Style.cornerRadius
              color: row.hovered && !row.editing ? Style.hoverFill : "transparent"

              Text {
                visible: row.showGroupHeading
                x: Style.space(6)
                y: Style.space(2)
                text: row.groupName === "" ? "Ungrouped" : row.groupName
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                enabled: !row.editing
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.hostWidget) root.hostWidget.toggleTask(row.modelData.id)
              }

              Rectangle {
                id: box
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                y: row.groupHeaderHeight + (row.editing
                  ? Style.space(3) + (editField.height - height) / 2
                  : (parent.height - row.groupHeaderHeight - height) / 2)
                width: Style.space(14)
                height: width
                radius: Math.min(3, Style.cornerRadius)
                color: row.modelData.done ? Color.accent : "transparent"
                border.width: 1
                border.color: row.modelData.done ? Color.accent : root.fg

                Text {
                  anchors.centerIn: parent
                  visible: row.modelData.done
                  text: "✓"
                  color: Color.background
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Text {
                id: label
                visible: !row.editing
                anchors.left: box.right
                anchors.leftMargin: Style.space(10)
                anchors.right: side.left
                anchors.rightMargin: Style.space(8)
                y: row.groupHeaderHeight + (parent.height - row.groupHeaderHeight - implicitHeight) / 2
                text: row.modelData.title
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: row.modelData.done ? Color.muted : root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.strikeout: row.modelData.done
              }

              // ---- Inline editor for the title or the deadline.
              Column {
                id: editColumn
                visible: row.editing
                anchors.left: box.right
                anchors.leftMargin: Style.space(6)
                anchors.right: parent.right
                y: row.groupHeaderHeight + Style.space(3)
                spacing: Style.space(4)

                TextField {
                  id: editField
                  width: parent.width
                  verticalPadding: Style.space(3)
                  foreground: root.fg
                  placeholderText: root.editMode === "due"
                    ? "17:00, +2h, tomorrow 9am, fri, 12/10…"
                    : (root.editMode === "group" ? "Group name (empty to ungroup)" : "")
                  onVisibleChanged: if (visible) {
                    text = root.editMode === "due"
                      ? (row.hasDue ? Due.editable(row.modelData.due) : "")
                      : (root.editMode === "group" ? row.groupName : row.modelData.title)
                    Qt.callLater(function() {
                      editField.forceActiveFocus()
                      editField.selectAll()
                    })
                  }
                  onAccepted: root.finishEditing(row.modelData.id, text)
                  Keys.onEscapePressed: root.cancelEditing()
                }

                Text {
                  visible: root.editMode === "due"
                  width: parent.width
                  leftPadding: Style.space(2)
                  text: root.duePreview(editField.text)
                  wrapMode: Text.Wrap
                  color: text.indexOf("Not understood") === 0 ? Color.urgent : Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Right side: countdown normally, actions on hover.
              Item {
                id: side
                visible: !row.editing
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                y: row.groupHeaderHeight + (parent.height - row.groupHeaderHeight - height) / 2
                width: Math.max(countdown.visible ? countdown.implicitWidth : 0, actions.implicitWidth)
                height: Math.max(countdown.implicitHeight, actions.implicitHeight)

                Text {
                  id: countdown
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  visible: row.hasDue && !row.modelData.done && !row.hovered
                  text: row.hasDue ? Due.countdown(row.modelData.due, root.now) : ""
                  color: row.hasDue ? root.dueColor(row.modelData.due) : Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Row {
                  id: actions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(12)
                  visible: row.hovered

                  Text {
                    text: "▦"
                    color: groupMouse.containsMouse ? Color.accent : Color.muted
                    font.pixelSize: Style.font.body

                    MouseArea {
                      id: groupMouse
                      anchors.fill: parent
                      anchors.margins: -4
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.startEditing(row.modelData.id, "group")
                    }
                  }

                  Text {
                    text: "⏱"
                    color: dueMouse.containsMouse ? Color.accent : Color.muted
                    font.pixelSize: Style.font.body

                    MouseArea {
                      id: dueMouse
                      anchors.fill: parent
                      anchors.margins: -4
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.startEditing(row.modelData.id, "due")
                    }
                  }

                  Text {
                    text: "✎"
                    color: editMouse.containsMouse ? Color.accent : Color.muted
                    font.pixelSize: Style.font.body

                    MouseArea {
                      id: editMouse
                      anchors.fill: parent
                      anchors.margins: -4
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.startEditing(row.modelData.id, "title")
                    }
                  }

                  Text {
                    text: "✕"
                    color: removeMouse.containsMouse ? Color.urgent : Color.muted
                    font.pixelSize: Style.font.body

                    MouseArea {
                      id: removeMouse
                      anchors.fill: parent
                      anchors.margins: -4
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.hostWidget) root.hostWidget.removeTask(row.modelData.id)
                    }
                  }
                }
              }
            }
          }

          // ---- Footer
          Text {
            visible: root.doneCount > 0
            anchors.right: parent.right
            text: "Clear completed"
            color: clearMouse.containsMouse ? Color.accent : Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.underline: clearMouse.containsMouse

            MouseArea {
              id: clearMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.hostWidget) root.hostWidget.clearDone()
            }
          }
        }
      }
    }
  }
}
