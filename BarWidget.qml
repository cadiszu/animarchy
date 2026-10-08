import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "animarchy"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  // ani-cli exits non-zero the moment it hands off to the detached player on
  // some setups; a quick running->stopped flip still lets the icon pulse.
  readonly property bool launching: launchProcess.running

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // Convenience: open the panel with the search field focused.
  function search() {
    open()
    if (panelLoader.item && typeof panelLoader.item.focusSearch === "function")
      panelLoader.item.focusSearch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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

  Process {
    id: launchProcess
    command: ["ani-cli", "-c"]
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf26c"
    active: root.launching || root.opened
    horizontalMargin: 7.5
    tooltipText: root.opened
      ? "ani-cli\nLeft click: close · Right click: hide"
      : "ani-cli\nLeft click: open · Right click: resume last episode"

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        // Without ani-cli there's nothing to resume: open the panel instead
        // so the install banner is visible. Panel may still be loading, in
        // which case fall through to the direct launch attempt.
        var panel = panelLoader.item
        if (panel && panel.aniCliPresent === false) { root.open(); return }
        if (!launchProcess.running) launchProcess.running = true
      } else {
        root.togglePanel()
      }
    }
  }
}