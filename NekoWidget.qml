import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Live bar widget for Neko: dot + pending count from the status file the
// Neko app mirrors on every snapshot. Click summons the companion panel
// (NekoPanel.qml). Plugin/host contract mirrors omarchy.clock: open/close/
// opened on the bar-widget root, Loader-owned panel, IpcHandler routing.
BarWidget {
  id: root
  moduleName: "rakha.neko"

  // ---- live model (status.json v1: sessions[] + pending[] + questions[]) ----
  property var sessions: []
  property var pendings: []
  property var questions: []
  property bool backendAlive: false
  property bool hadPending: false

  readonly property int waitingCount: pendings.length + questions.length
  readonly property string worst: {
    if (waitingCount > 0) return "waiting";
    var rank = { error: 5, waiting_permission: 5, working: 4, tool_running: 4, completed: 2, idle: 1, disconnected: 0 };
    var best = "idle";
    var bestRank = -1;
    if (sessions.length === 0) return "idle";
    for (var i = 0; i < sessions.length; i++) {
      var s = sessions[i].status;
      var r = (s in rank) ? rank[s] : -1;
      if (r > bestRank) { bestRank = r; best = s; }
    }
    return best;
  }
  readonly property string dotColor: {
    if (!backendAlive) return "#484f58";
    switch (worst) {
    case "waiting": case "waiting_permission": return "#ffb224";
    case "error": return "#f85149";
    case "working": case "tool_running": return "#58a6ff";
    case "completed": return "#3fb950";
    default: return "#8b949e";
    }
  }
  readonly property string statusPath: {
    try {
      var s = Quickshell.env("NEKO_STATUS");
      if (s) return s;
      var x = Quickshell.env("XDG_RUNTIME_DIR");
      if (x) return x + "/neko-status.json";
    } catch (e) {}
    return "/tmp/neko-status.json";
  }
  readonly property string tooltipText: {
    if (!backendAlive) return "Neko — app not running";
    if (waitingCount > 0) return "Neko — " + waitingCount + " request(s) waiting";
    if (sessions.length === 0) return "Neko — waiting for OpenCode";
    return "Neko — " + sessions.length + " session(s)";
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
    clearStatus();
  }

  function clearStatus() {
    sessions = [];
    pendings = [];
    questions = [];
    backendAlive = false;
  }

  function refresh() {
    statusFile.reload();
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh();
  }

  // ---- panel contract (omarchy.clock shape) ----
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    hadPending = waitingCount > 0;
    refresh();
    if (panelLoader.item) panelLoader.item.open();
  }

  function close() {
    hadPending = false;
    if (panelLoader.item) panelLoader.item.close();
  }

  function togglePanel() {
    if (waitingCount > 0) hadPending = true;
    if (panelLoader.item) panelLoader.item.toggle();
    else root.open();
  }

  function injectPanel() {
    var target = panelLoader.item;
    if (!target) return;
    if ("bar" in target) target.bar = root.bar;
    if ("settings" in target) target.settings = root.settings;
    if ("anchorItem" in target) target.anchorItem = button;
    if ("hostWidget" in target) target.hostWidget = root;
  }

  // Auto-close: opened for waiting requests and they all resolved.
  onWaitingCountChanged: {
    if (hadPending && waitingCount === 0) root.close();
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.parseStatus(text())
    onLoadFailed: root.clearStatus()
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: statusFile.reload()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("NekoPanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel();
      Qt.callLater(root.injectPanel);
    }
  }

  IpcHandler {
    target: "rakha.neko"

    function refresh(): void { root.refresh(); }
    function open(): void { root.open(); }
    function close(): void { root.close(); }
    function show(): void { root.open(); }
    function hide(): void { root.close(); }
    function toggle(): void { root.togglePanel(); }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltipText
    onPressed: root.togglePanel()
    iconComponent: nekoIcon
  }

  Component {
    id: nekoIcon
    Item {
      Row {
        anchors.centerIn: parent
        spacing: 3
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "●"
          color: root.dotColor
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.waitingCount > 0
          text: root.waitingCount
          color: "#ffb224"
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
