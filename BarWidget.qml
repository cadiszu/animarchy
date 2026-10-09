import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Effects
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.cadiszu.animarchy"

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

  // The bar mark is the eye SVG recolored to the theme foreground, going accent
  // while an episode plays. The panel's footer episode is the only record of
  // "something is playing", so read it from the loader.
  readonly property bool playing: panelLoader.item
    ? panelLoader.item.nowPlayingEp !== "" && panelLoader.item.nowPlayingEp !== "-"
    : false
  readonly property color iconColor: root.playing
    ? Color.accent
    : (root.bar ? root.bar.barForeground : Color.foreground)

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Fallback glyph, kept so the slot still has content if the SVG fails to
    // load; labelVisible hides the text once the SVG renders. Keeping a
    // non-empty text also preserves the slot's implicit width.
    text: "\uf26c"
    labelVisible: false
    active: root.launching || root.opened
    horizontalMargin: 7.5
    tooltipText: root.opened
      ? "animarchy\nLeft click: close · Right click: resume last episode"
      : "animarchy\nLeft click: open · Right click: resume last episode"

    Image {
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: width
      fillMode: Image.PreserveAspectFit
      source: Qt.resolvedUrl("assets/animarchy.svg")
      // Decode at physical pixels: sourceSize is logical, which leaves the
      // mark upscaled and soft on a HiDPI bar.
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      visible: status === Image.Ready
      layer.enabled: true
      layer.effect: MultiEffect {
        colorization: 1
        colorizationColor: root.iconColor

        Behavior on colorizationColor {
          ColorAnimation { duration: 160 }
        }
      }
    }

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