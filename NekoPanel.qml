import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Companion panel for the Neko bar widget: sessions + permission cards.
// Host contract mirrors omarchy.clock Panel: BarWidget.qml owns this file
// through a Loader and injects bar/settings/anchorItem/hostWidget.
// Self-contained: reads the status file itself so content never depends on
// widget internals. v1: sessions + permissions (questions ride WS3).
Panel {
  id: root
  moduleName: "rakha.neko"
  ipcTarget: "rakha.neko"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var sessions: []
  property var pendings: []
  property bool backendAlive: false
  property string lastError: ""

  readonly property var statusLabels: ({
    "disconnected": "Disconnected",
    "idle": "Idle",
    "working": "Working",
    "tool_running": "Tool running",
    "waiting_permission": "Needs you",
    "completed": "Done",
    "error": "Error"
  })

  function statusDot(s) {
    switch (s) {
    case "waiting_permission": return "#ffb224";
    case "error": return "#f85149";
    case "working": case "tool_running": return "#58a6ff";
    case "completed": return "#3fb950";
    default: return "#8b949e";
    }
  }

  function statusPath() {
    try {
      var s = Quickshell.env("NEKO_STATUS");
      if (s) return s;
      var x = Quickshell.env("XDG_RUNTIME_DIR");
      if (x) return x + "/neko-status.json";
    } catch (e) {}
    return "/tmp/neko-status.json";
  }

  function refresh() {
    statusFile.reload();
  }

  function parseStatus(text) {
    try {
      var v = JSON.parse(text);
      if (v && Array.isArray(v.sessions)) {
        sessions = v.sessions;
        pendings = Array.isArray(v.pending) ? v.pending : [];
        backendAlive = true;
        return;
      }
    } catch (e) {}
    sessions = [];
    pendings = [];
    backendAlive = false;
  }

  function open() {
    lastError = "";
    refresh();
    root.controller.show();
  }

  function close() {
    root.controller.hide();
  }

  function toggle() {
    if (root.opened) root.close();
    else root.open();
  }

  function answer(requestId, decision) {
    lastError = "";
    replyProc.command = ["neko", "reply", "permission", requestId, decision];
    replyProc.running = true;
  }

  implicitWidth: 320
  implicitHeight: content.implicitHeight + 20

  FileView {
    id: statusFile
    path: root.statusPath()
    watchChanges: true
    printErrors: false
    onLoaded: root.parseStatus(text())
    onLoadFailed: { root.sessions = []; root.pendings = []; root.backendAlive = false; }
  }

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: statusFile.reload()
  }

  Process {
    id: replyProc
    onExited: function(code) {
      if (code !== 0) root.lastError = "reply failed — is Neko installed and running?";
    }
  }

  Column {
    id: content
    anchors.fill: parent
    anchors.margins: 10
    spacing: 8

    Row {
      width: parent.width
      Text {
        text: "Neko"
        color: "#fff"
        font.pixelSize: 13
        font.bold: true
      }
      Item { width: 1; height: 1; Layout.fillWidth: true }
      // plain clickable close, primitives only (no shell button API assumed)
      Text {
        text: "✕"
        color: "#8b949e"
        font.pixelSize: 13
        MouseArea {
          anchors.fill: parent
          onClicked: root.close()
        }
      }
    }

    Repeater {
      model: root.pendings
      delegate: Rectangle {
        property string reqId: modelData.requestId
        width: content.width
        height: cardCol.implicitHeight + 16
        radius: 8
        color: "rgba(255,178,36,0.08)"
        border.width: 1
        border.color: "#ffb224"
        Column {
          id: cardCol
          anchors.fill: parent
          anchors.margins: 8
          spacing: 6
          Text {
            width: parent.width
            text: "Permission requested"
            color: "#fff"
            font.pixelSize: 12
            font.bold: true
          }
          Text {
            width: parent.width
            text: (modelData.action || "unknown") + (modelData.resource ? " " + modelData.resource : "")
            color: "#fff"
            opacity: 0.85
            font.pixelSize: 11
            font.family: "monospace"
            elide: Text.ElideRight
          }
          Row {
            spacing: 6
            Repeater {
              model: [["once", "Allow", "#1f6feb"], ["always", "Always", "rgba(255,255,255,0.08)"], ["deny", "Deny", "rgba(248,81,73,0.25)"]]
              delegate: Rectangle {
                width: (content.width - 28) / 3
                height: 28
                radius: 6
                color: modelData[2]
                border.width: 1
                border.color: "#30363d"
                Text {
                  anchors.centerIn: parent
                  text: modelData[1]
                  color: "#fff"
                  font.pixelSize: 12
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.answer(reqId, modelData[0])
                }
              }
            }
          }
        }
      }
    }

    Text {
      visible: root.lastError !== ""
      width: parent.width
      text: root.lastError
      color: "#f85149"
      font.pixelSize: 11
      wrapMode: Text.Wrap
    }

    Text {
      visible: root.backendAlive && root.sessions.length === 0
      width: parent.width
      text: "No sessions — waiting for OpenCode."
      color: "#8b949e"
      font.pixelSize: 11
    }

    Text {
      visible: !root.backendAlive
      width: parent.width
      text: "Neko app not running."
      color: "#8b949e"
      font.pixelSize: 11
    }

    Repeater {
      model: root.sessions
      delegate: Row {
        width: content.width
        spacing: 8
        Text {
          text: "●"
          color: root.statusDot(modelData.status)
          font.pixelSize: 11
        }
        Text {
          width: parent.width - 90
          text: modelData.project || modelData.id
          color: "#fff"
          font.pixelSize: 11
          elide: Text.ElideRight
        }
        Text {
          text: root.statusLabels[modelData.status] || modelData.status
          color: "#8b949e"
          font.pixelSize: 11
        }
      }
    }
  }
}
