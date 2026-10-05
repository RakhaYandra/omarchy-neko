import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Skeleton bar widget (Fase 0): static icon only. Live status (Fase 2) will
// poll the Neko status file and summon a panel with sessions/permissions.
BarWidget {
  id: root
  moduleName: "rakha.neko"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "●"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Neko (skeleton — live status coming soon)"
    onPressed: {
      // Fase 2: togglePanel() with sessions/permissions.
    }
  }
}
