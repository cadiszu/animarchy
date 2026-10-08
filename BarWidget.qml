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
    // Fallback for right-click resume before the panel has loaded. Runs in a
    // real terminal because ani-cli -c is interactive (fzf); headless it
    // has no TTY and hangs. Holds the window open on error like Panel.launch.
    command: ["omarchy-launch-tui", "--app-id=TUI.float", "sh", "-c", "ani-cli -c; _rc=$?; if [ $_rc -ne 0 ]; then printf '\\n\\033[1;31mani-cli exited (%s).\\033[0m Press Enter to close.\\n' \"$_rc\"; read -r _; fi"]
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf26c"
    active: root.launching || root.opened
    horizontalMargin: 7.5
    tooltipText: root.opened
      ? "ani-cli\nLeft click: close · Right click: resume last episode"
      : "ani-cli\nLeft click: open · Right click: resume last episode"

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        // Without ani-cli there's nothing to resume: open the panel instead
        // so the install banner is visible. Only trust the flag once the
        // probe has finished; before that, attempt the resume.
        var panel = panelLoader.item
        if (panel && panel.probeDone === true && panel.aniCliPresent === false) { root.open(); return }
        // Prefer the panel path so user options (quality/dub/skip) apply.
        if (panel && typeof panel.continueWatching === "function") { panel.continueWatching(); return }
        if (!launchProcess.running) launchProcess.running = true
      } else {
        root.togglePanel()
      }
    }
  }
}