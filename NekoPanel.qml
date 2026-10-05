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
  // Donut data: [{label, color, count}] + total, rebuilt on every parse.
  property var bucketRows: []
  property int bucketTotal: 0

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

  onBucketRowsChanged: donut.requestPaint()

  // HUD stream helpers (design tokens: JetBrains Mono, tabular ages).
  function shortId(id) {
    if (!id || id.length <= 18) return id || "";
    return id.slice(0, 10) + "…" + id.slice(-6);
  }

  function ageOf(ts) {
    var s = Math.max(0, Math.round((Date.now() - ts) / 1000));
    if (s < 60) return s + "s";
    var m = Math.floor(s / 60);
    if (m < 60) return m + "m";
    return Math.floor(m / 60) + "h";
  }

  function pillColor(status) {
    if (status === "waiting_permission") return "#ffb224";
    if (status === "error") return "#f85149";
    if (status === "working" || status === "tool_running") return "#58a6ff";
    if (status === "completed") return "#3fb950";
    return "#8b949e";
  }
  function heroPose() {
    if (!backendAlive || sessions.length === 0) return "idle";
    var rank = { error: 5, waiting_permission: 5, working: 4, tool_running: 4, completed: 2, idle: 1, disconnected: 0 };
    var best = "idle";
    var bestRank = -1;
    for (var i = 0; i < sessions.length; i++) {
      var s = sessions[i].status;
      var r = (s in rank) ? rank[s] : -1;
      if (r > bestRank) { bestRank = r; best = s; }
    }
    if (pendings.length + questions.length > 0 && bestRank < 5
        && (best === "working" || best === "tool_running" || best === "idle")) {
      return "waiting_permission";
    }
    return (best === "waiting") ? "waiting_permission" : best;
  }

  function heroStat() {
    var waiting = pendings.length + questions.length;
    if (waiting > 0) return { big: String(waiting), sub: waiting === 1 ? "needs you" : "need you" };
    if (sessions.length > 0) return { big: String(sessions.length), sub: sessions.length === 1 ? "session" : "sessions" };
    return { big: "—", sub: "waiting for OpenCode" };
  }

  // Donut buckets from live sessions (counts, stable order/colors).
  function rebuildBuckets() {
    var defs = [
      { key: "waiting_permission", label: "Needs you", color: "#ffb224" },
      { key: "working", label: "Working", color: "#58a6ff" },
      { key: "completed", label: "Done", color: "#3fb950" },
      { key: "idle", label: "Idle", color: "#8b949e" },
      { key: "error", label: "Error", color: "#f85149" }
    ];
    var counts = {};
    for (var i = 0; i < sessions.length; i++) {
      var s = sessions[i].status;
      if (s === "tool_running") s = "working";
      else if (s === "disconnected") s = "idle";
      counts[s] = (counts[s] || 0) + 1;
    }
    var rows = [];
    var total = 0;
    for (var j = 0; j < defs.length; j++) {
      var c = counts[defs[j].key] || 0;
      if (c > 0) { rows.push({ label: defs[j].label, color: defs[j].color, count: c }); total += c; }
    }
    bucketRows = rows;
    bucketTotal = total;
  }

  function parseStatus(text) {
    try {
      var v = JSON.parse(text);
      if (v && Array.isArray(v.sessions)) {
        sessions = v.sessions;
        pendings = Array.isArray(v.pending) ? v.pending : [];
        questions = Array.isArray(v.questions) ? v.questions : [];
        backendAlive = true;
        rebuildBuckets();
        return;
      }
    } catch (e) {}
    sessions = [];
    pendings = [];
    questions = [];
    backendAlive = false;
    rebuildBuckets();
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
        // Explicit width (never parent-bound): parent chain sizes from us
        // via fittedContentHeight, so parent.width here loops. Mirrors clock.
        width: Style.space(340) - 20
        x: 10
        y: 10
        spacing: 8

    Row {
      width: parent.width
      Text {
        text: "Neko"
        color: "#c9d1d9"
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

    Row {
      width: parent.width
      spacing: 12
      visible: root.backendAlive
      Image {
        source: "assets/neko-" + root.heroPose() + ".png"
        width: 64
        height: 64
        smooth: false
        mipmap: false
        fillMode: Image.PreserveAspectFit
      }
      Column {
        spacing: 2
        Text {
          text: root.heroStat().big
          color: "#c9d1d9"
          font.pixelSize: 26
          font.bold: true
        }
        Text {
          text: root.heroStat().sub
          color: "#8b949e"
          font.pixelSize: 11
        }
        Text {
          text: Qt.formatDate(new Date(), "d MMM yyyy")
          color: "#8b949e"
          font.pixelSize: 11
        }
      }
    }

    Row {
      width: parent.width
      spacing: 12
      visible: root.backendAlive && root.bucketTotal > 0
      Item {
        width: 120
        height: 120
        Canvas {
          id: donut
          anchors.fill: parent
          onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (root.bucketTotal <= 0) return;
            ctx.lineWidth = 14;
            var cx = width / 2, cy = height / 2, r = width / 2 - 8;
            var a0 = -Math.PI / 2;
            for (var i = 0; i < root.bucketRows.length; i++) {
              var frac = root.bucketRows[i].count / root.bucketTotal;
              var a1 = a0 + frac * Math.PI * 2;
              ctx.strokeStyle = root.bucketRows[i].color;
              ctx.beginPath();
              ctx.arc(cx, cy, r, a0, Math.max(a1, a0 + 0.02));
              ctx.stroke();
              a0 = a1;
            }
          }
        }
        Text {
          anchors.centerIn: parent
          text: root.heroStat().big
          color: "#c9d1d9"
          font.pixelSize: 18
          font.bold: true
        }
      }
      Column {
        spacing: 6
        Repeater {
          model: root.bucketRows
          delegate: Row {
            width: contentColumn.width - 132
            spacing: 8
            Rectangle {
              width: 7
              height: 7
              radius: 3.5
              color: modelData.color
            }
            Text {
              text: modelData.label
              color: "#c9d1d9"
              font.pixelSize: 12
            }
            Item { width: 1; height: 1; Layout.fillWidth: true }
            Text {
              text: modelData.count
              color: "#c9d1d9"
              font.pixelSize: 12
            }
          }
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
        color: "#14ffb224"
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
            color: "#c9d1d9"
            font.pixelSize: 12
            font.bold: true
          }
          Text {
            width: parent.width
            text: (modelData.action || "unknown") + (modelData.resource ? " " + modelData.resource : "")
            color: "#c9d1d9"
            opacity: 0.85
            font.pixelSize: 11
            font.family: "monospace"
            elide: Text.ElideRight
          }
          Row {
            spacing: 6
            Repeater {
              model: [["once", "Allow", "#1f6feb"], ["always", "Always", "#14ffffff"], ["deny", "Deny", "#40f85149"]]
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
                  color: "#c9d1d9"
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
        color: "#1458a6ff"
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
            color: "#c9d1d9"
            font.pixelSize: 12
            font.bold: true
          }
          Text {
            width: parent.width
            visible: item !== null
            text: item ? ((item.header ? item.header + ": " : "") + item.question) : ""
            color: "#c9d1d9"
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
              color: picked.indexOf(optLabel) >= 0 ? "#1f6feb" : "#0fffffff"
              border.width: 1
              border.color: "#30363d"
              Text {
                anchors.centerIn: parent
                text: optLabel
                color: "#c9d1d9"
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
                color: "#c9d1d9"
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
              color: "#40f85149"
              border.width: 1
              border.color: "#30363d"
              Text {
                anchors.centerIn: parent
                text: "Dismiss"
                color: "#c9d1d9"
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
          width: parent.width - 150
          text: root.shortId(modelData.id)
          color: "#c9d1d9"
          font.pixelSize: 11
          font.family: "JetBrains Mono"
          elide: Text.ElideRight
        }
        Text {
          text: root.ageOf(modelData.lastActivityAt)
          color: "#6b7d91"
          font.pixelSize: 10
          font.family: "JetBrains Mono"
        }
        Item { width: 1; height: 1; Layout.fillWidth: true }
        Rectangle {
          height: 18
          width: pillLabel.implicitWidth + 12
          radius: 4
          color: "transparent"
          border.width: 1
          border.color: root.pillColor(modelData.status)
          Text {
            id: pillLabel
            anchors.centerIn: parent
            text: root.statusLabels[modelData.status] || modelData.status
            color: root.pillColor(modelData.status)
            font.pixelSize: 9
            font.bold: true
          }
        }
      }
    }
  }
  }
}
}
