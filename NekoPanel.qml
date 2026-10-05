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
  property var questions: []
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
        questions = Array.isArray(v.questions) ? v.questions : [];
        backendAlive = true;
        return;
      }
    } catch (e) {}
    sessions = [];
    pendings = [];
    questions = [];
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

  function answerQuestion(requestId, labels) {
    lastError = "";
    replyProc.command = ["neko", "reply", "question", requestId].concat(labels);
    replyProc.running = true;
  }

  function rejectQuestion(requestId) {
    lastError = "";
    replyProc.command = ["neko", "reject", "question", requestId];
    replyProc.running = true;
  }

  FileView {
    id: statusFile
    path: root.statusPath()
    watchChanges: true
    printErrors: false
    onLoaded: root.parseStatus(text())
    onLoadFailed: { root.sessions = []; root.pendings = []; root.questions = []; root.backendAlive = false; }
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

  // Popout window (clock/weather shape): the Panel base above only owns
  // lifecycle; this KeyboardPanel is the visible popup anchored to the bar.
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight + 20)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    // Flickable hosts the column (clock shape): the column must size from
    // its children, never anchors.fill (that collapses to zero height
    // against the fitted popup and renders nothing).
    Flickable {
      anchors.fill: parent
      contentWidth: contentColumn.width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height || contentWidth > width

      Column {
        id: contentColumn
        width: parent.width - 20
        x: 10
        y: 10
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
        width: contentColumn.width
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
                width: (contentColumn.width - 28) / 3
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

    Repeater {
      model: root.questions
      delegate: Rectangle {
        property string reqId: modelData.requestId
        property var item: (modelData.questions && modelData.questions.length > 0) ? modelData.questions[0] : null
        property int extra: (modelData.questions ? modelData.questions.length : 0) - 1
        property var picked: []
        width: contentColumn.width
        height: qCol.implicitHeight + 16
        radius: 8
        color: "rgba(88,166,255,0.08)"
        border.width: 1
        border.color: "#58a6ff"
        Column {
          id: qCol
          anchors.fill: parent
          anchors.margins: 8
          spacing: 6
          Text {
            width: parent.width
            text: "Question needs an answer"
            color: "#fff"
            font.pixelSize: 12
            font.bold: true
          }
          Text {
            width: parent.width
            visible: item !== null
            text: item ? ((item.header ? item.header + ": " : "") + item.question) : ""
            color: "#fff"
            font.pixelSize: 12
            font.bold: true
            wrapMode: Text.Wrap
          }
          Text {
            width: parent.width
            visible: item === null || extra > 0
            text: item === null
              ? "No options provided — answer in the terminal."
              : (extra + 1) + " questions at once — answer in the terminal."
            color: "#8b949e"
            font.pixelSize: 11
            wrapMode: Text.Wrap
          }
          Text {
            width: parent.width
            visible: item !== null && extra <= 0 && item.custom === true
            text: "Free-text answers unsupported — pick an option or use the terminal."
            color: "#8b949e"
            font.pixelSize: 11
            wrapMode: Text.Wrap
          }
          Repeater {
            model: (item !== null && extra <= 0 && Array.isArray(item.options)) ? item.options : []
            delegate: Rectangle {
              property string optLabel: modelData.label
              width: contentColumn.width
              height: 26
              radius: 6
              color: picked.indexOf(optLabel) >= 0 ? "#1f6feb" : "rgba(255,255,255,0.06)"
              border.width: 1
              border.color: "#30363d"
              Text {
                anchors.centerIn: parent
                text: optLabel
                color: "#fff"
                font.pixelSize: 12
              }
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  if (item.multiple === true) {
                    var next = picked.slice();
                    var at = next.indexOf(optLabel);
                    if (at >= 0) next.splice(at, 1);
                    else next.push(optLabel);
                    picked = next;
                  } else {
                    root.answerQuestion(reqId, [optLabel]);
                  }
                }
              }
            }
          }
          Row {
            spacing: 6
            visible: item !== null && extra <= 0
            Rectangle {
              visible: item !== null && item.multiple === true
              width: (contentColumn.width - 14) / 2
              height: 28
              radius: 6
              color: "#1f6feb"
              border.width: 1
              border.color: "#30363d"
              opacity: picked.length === 0 ? 0.5 : 1
              Text {
                anchors.centerIn: parent
                text: "Answer"
                color: "#fff"
                font.pixelSize: 12
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                onClicked: { if (picked.length > 0) root.answerQuestion(reqId, picked); }
              }
            }
            Rectangle {
              width: (item !== null && item.multiple === true) ? (contentColumn.width - 14) / 2 : contentColumn.width - 12
              height: 28
              radius: 6
              color: "rgba(248,81,73,0.25)"
              border.width: 1
              border.color: "#30363d"
              Text {
                anchors.centerIn: parent
                text: "Dismiss"
                color: "#fff"
                font.pixelSize: 12
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.rejectQuestion(reqId)
              }
            }
          }
        }
      }
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
        width: contentColumn.width
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
}
}
