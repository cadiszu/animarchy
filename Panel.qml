import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "animarchy"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string histDir: stateHome + "/ani-cli"
  readonly property string histFile: histDir + "/ani-hsts"

  // --- options ---
  readonly property bool dubEnabled: setting("dub", false) === true
  readonly property bool downloadEnabled: setting("download", false) === true
  readonly property bool skipIntroEnabled: setting("skipIntro", false) === true
  readonly property bool nextepEnabled: setting("nextep", false) === true
  readonly property string downloadDir: String(setting("downloadDir", Quickshell.env("HOME") + "/Downloads"))
  readonly property string quality: String(setting("quality", "best"))
  readonly property string episodeRange: String(setting("episodes", ""))
  readonly property int historyLimit: Math.max(1, Number(setting("historyLimit", 8)))

  property var history: []
  property string statusText: ""

  // ---- native browse (search + episode grid) ----
  property var searchResults: []
  property var episodeList: []
  property var episodeView: []
  property bool searching: false
  property bool loadingEpisodes: false
  property string selectedAnimeId: ""
  property string selectedAnimeTitle: ""
  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("anicli-data")).replace(/^file:\/\//, ""))
  readonly property string playerPath: decodeURIComponent(String(Qt.resolvedUrl("launch-mpv.sh")).replace(/^file:\/\//, ""))
  readonly property string historyPath: decodeURIComponent(String(Qt.resolvedUrl("record-history.sh")).replace(/^file:\/\//, ""))
  property string nowPlayingTitle: ""
  property string nowPlayingEp: ""
  property bool showSettings: false
  property int activeTab: 0
  // Pending Prev/Next step waiting on an episode-list reload.
  property int pendingStep: 0
  // Anime id the in-flight grid load belongs to. A stale arrival after
  // navigating elsewhere is dropped, never applied to the wrong title.
  property string loadingEpisodesId: ""
  // True when nowPlayingEpisodes holds the complete list rather than the
  // single-episode stub used to start playback instantly.
  property bool nowPlayingFullList: false

  // Optional companion binaries. ani-cli aborts the whole launch when a flag
  // needs a tool that is not installed (e.g. "--skip" without ani-skip), so we
  // probe once at startup and only pass flags we can actually honour.
  property bool probeDone: false
  property bool aniSkipPresent: false
  property bool aniCliPresent: false
  property int depRefreshAttempts: 0

  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string ff: Style.font.family

  function persistSetting(name, value) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[name] = value
    root.settings = entry
    if (root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function parseHistory(content) {
    var out = []
    var lines = String(content || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts.length >= 3 && parts[0] !== "" && parts[1] !== "") {
        out.push({ episode: parts[0], id: parts[1], title: parts[2] })
      }
    }
    // One row per title: keep only the most recent entry for each anime id,
    // newest first. The file can hold repeats (e.g. rapid replays racing
    // each other), so this is enforced at display time too.
    var seen = {}
    var deduped = []
    for (var j = out.length - 1; j >= 0; j--) {
      var e = out[j]
      if (!seen[e.id]) { seen[e.id] = true; deduped.push(e) }
    }
    return deduped
  }

  // Options that describe how ani-cli should behave. Reused by every launch.
  // Flags whose companion tool is missing are omitted: ani-cli treats a
  // missing dependency as fatal, and a fatal aborts the whole launch.
  function optionArgs() {
    var args = ["-q", root.quality]
    if (root.dubEnabled) args.push("--dub")
    if (root.downloadEnabled) args.push("-d")
    if (root.skipIntroEnabled && root.aniSkipPresent) args.push("--skip")
    if (root.nextepEnabled) args.push("-N")
    if (root.episodeRange.trim() !== "") args.push("-e", root.episodeRange.trim())
    return args
  }

  function downloadRangeSpec() {
    var nums = []
    for (var i = 0; i < root.episodeView.length; i++) {
      var n = parseInt(root.episodeView[i].ep, 10)
      if (!isNaN(n)) nums.push(n)
    }
    if (nums.length === 0) {
      var raw = []
      for (var j = 0; j < root.episodeView.length; j++) raw.push(String(root.episodeView[j].ep))
      return raw.join(" ")
    }
    nums.sort(function(a, b) { return a - b })
    var parts = []
    var s = nums[0], p = nums[0]
    for (var k = 1; k < nums.length; k++) {
      if (nums[k] === p + 1) { p = nums[k]; continue }
      parts.push(s === p ? String(s) : (s + "-" + p))
      s = p = nums[k]
    }
    parts.push(s === p ? String(s) : (s + "-" + p))
    return parts.join(" ")
  }

  function downloadEpisodes() {
    if (root.episodeView.length === 0 || root.selectedAnimeTitle === "") return
    var args = ["-q", root.quality]
    if (root.dubEnabled) args.push("--dub")
    args.push("-d")
    if (root.skipIntroEnabled && root.aniSkipPresent) args.push("--skip")
    if (root.nextepEnabled) args.push("-N")
    var spec = root.downloadRangeSpec()
    if (spec !== "") args.push("-e", spec)
    args.push(root.selectedAnimeTitle)
    launch(args, root.selectedAnimeTitle)
  }

  // Launch ani-cli inside the default Omarchy terminal and pull the popup down.
  // ani-cli is an interactive TUI (fzf + mpv), so it needs a real terminal.
  // The TUI.float app-id gets Omarchy's floating + centered window treatment,
  // so the window is visible instead of opening tiled behind other windows.
  // We wrap the call in a shell that holds the window open if ani-cli exits
  // immediately, so a dependency error is actually readable instead of a blink.
  function launch(args, subdir) {
    var prefix = ""
    if (args.indexOf("-d") !== -1) {
      var base = String(root.downloadDir || "").trim()
      if (base === "~") base = Quickshell.env("HOME")
      else if (base.indexOf("~/") === 0) base = Quickshell.env("HOME") + base.slice(1)
      if (base === "") base = Quickshell.env("HOME") + "/Downloads"
      var dir = base
      if (subdir !== undefined && String(subdir) !== "") {
        // Upstream titles can contain "/" (e.g. "Fate/stay night"); keep the
        // download inside one folder instead of creating nested directories.
        var safeSub = String(subdir).replace(/\//g, "_")
        dir = base + "/" + safeSub
      }
      if (dir !== "" && dir !== "/") {
        prefix = "mkdir -p " + shellQuote(dir) + " && ANI_CLI_DOWNLOAD_DIR=" + shellQuote(dir) + " "
      }
    }
    var cli = prefix + "ani-cli " + args.map(shellQuote).join(" ")
    var wrapped = cli + "; _rc=$?; if [ $_rc -ne 0 ]; then "
      + "printf '\\n\\033[1;31mani-cli exited (%s).\\033[0m "
      + "Press Enter to close.\\n' \"$_rc\"; read -r _; fi"
    Quickshell.execDetached([
      "omarchy-launch-tui", "--app-id=TUI.float", "sh", "-c", wrapped
    ])
    statusText = "Launching ani-cli…"
    close()
  }

  // POSIX-safe single-quote quoting for embedding argv into the sh -c wrapper.
  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function startDepRefresh() {
    root.depRefreshAttempts = 0
    depRefresh.restart()
  }

  property bool playingEpisode: false
  property string currentPlayEp: ""
  property string nowPlayingAnimeId: ""
  property var nowPlayingEpisodes: []

  // True when the episode number passes the Episodes field
  // (e.g. "", "5", "5-100", "1-3 5"). Unparseable input shows all.
  function episodeInRange(ep) {
    var spec = String(root.episodeRange || "").trim()
    if (spec === "") return true
    var n = parseInt(ep, 10)
    if (isNaN(n)) return true
    var tokens = spec.split(/[\s,]+/)
    var anyValid = false
    for (var i = 0; i < tokens.length; i++) {
      var m = tokens[i].match(/^(\d+)(?:-(\d+))?$/)
      if (!m) continue
      anyValid = true
      var lo = parseInt(m[1], 10)
      var hi = m[2] !== undefined ? parseInt(m[2], 10) : lo
      if (hi < lo) { var t = lo; lo = hi; hi = t }
      if (n >= lo && n <= hi) return true
    }
    return !anyValid
  }

  function refreshEpisodeView() {
    var out = []
    for (var i = 0; i < root.episodeList.length; i++) {
      var e = root.episodeList[i]
      if (root.episodeInRange(e.ep)) out.push(e)
    }
    root.episodeView = out
  }

  function browseSearch() {
    var q = searchField.text.trim()
    if (q === "") { statusText = "Type an anime name…"; return }
    // Native search uses the python helper + curl, not the ani-cli binary,
    // so it works even before the presence probe finishes or when only
    // terminal flows need ani-cli.
    root.pendingStep = 0
    root.activeTab = 0
    root.searching = true
    root.searchResults = []
    root.selectedAnimeId = ""
    root.episodeList = []
    root.episodeView = []
    root.statusText = "Searching…"
    searchProc.command = ["python3", root.helperPath, "search", q]
    searchProc.running = true
  }

  function selectAnime(id, title) {
    root.pendingStep = 0
    root.selectedAnimeId = id
    root.selectedAnimeTitle = title
    root.episodeList = []
    root.episodeView = []
    root.loadingEpisodes = true
    root.loadingEpisodesId = id
    root.statusText = "Loading episodes…"
    // A previous load still flying is stale: stop it so its late arrival
    // can't overwrite this one (its death notice self-heals below).
    if (episodesProc.running) episodesProc.running = false
    episodesProc.command = ["python3", root.helperPath, "episodes", id]
    episodesProc.running = true
  }

  function clearSelection() {
    root.pendingStep = 0
    root.selectedAnimeId = ""
    root.selectedAnimeTitle = ""
    root.episodeList = []
    root.episodeView = []
  }

  function playEpisode(ep, fullList) {
    // Native resolve + mpv playback; the ani-cli binary is only needed for
    // terminal flows (continue/download), not for this path.
    nowPlayingTitle = root.selectedAnimeTitle
    nowPlayingEp = ep
    nowPlayingAnimeId = root.selectedAnimeId
    // Snapshot a copy: later searches replace episodeList wholesale and must
    // not disturb the stepping order.
    nowPlayingEpisodes = root.episodeList.slice()
    root.nowPlayingFullList = (fullList === true)
    root.currentPlayEp = ep
    root.playingEpisode = true
    root.statusText = "Resolving stream…"
    playProc.command = ["python3", root.helperPath, "play", root.selectedAnimeId, ep, root.dubEnabled ? "dub" : "sub", root.quality]
    playProc.running = true
  }

  function stepEpisode(delta) {
    if (root.nowPlayingEp === "") return
    var list = root.nowPlayingEpisodes
    if (!list || list.length === 0 || !root.nowPlayingFullList) {
      // No complete grid for this title: the history resume plays instantly
      // off a stub, and the full list follows in the background. Fetch (or
      // wait for) it, then step once it arrives.
      if (root.nowPlayingAnimeId === "") {
        root.statusText = "Episode list isn't loaded. Open the episode grid (☰) first."
        return
      }
      if (episodesProc.running) {
        // A load is already flying: queue the step (a mismatch is dropped
        // on arrival, never applied to the wrong list).
        if (root.nowPlayingAnimeId !== "") root.pendingStep = delta
        return
      }
      if (root.loadingEpisodes) return
      root.pendingStep = delta
      root.selectedAnimeId = root.nowPlayingAnimeId
      root.selectedAnimeTitle = root.nowPlayingTitle
      root.episodeList = []
      root.episodeView = []
      root.loadingEpisodes = true
      root.loadingEpisodesId = root.nowPlayingAnimeId
      root.statusText = "Loading episodes…"
      if (episodesProc.running) episodesProc.running = false
      episodesProc.command = ["python3", root.helperPath, "episodes", root.nowPlayingAnimeId]
      episodesProc.running = true
      return
    }
    root.applyStep(delta)
  }

  function applyStep(delta) {
    var list = root.nowPlayingEpisodes
    if (!list || list.length === 0 || root.nowPlayingEp === "") return
    var idx = -1
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].ep) === String(root.nowPlayingEp)) { idx = i; break }
    }
    if (idx < 0) { root.statusText = "Current episode isn't in the loaded list."; return }
    var n = idx + delta
    if (n < 0) { root.statusText = "Already at the first episode."; return }
    if (n >= list.length) { root.statusText = "You're at the latest listed episode."; return }
    var np = list[n]
    root.selectedAnimeTitle = root.nowPlayingTitle
    root.selectedAnimeId = root.nowPlayingAnimeId
    playEpisode(np.ep, true)
  }

  function prevEpisode() { stepEpisode(-1) }
  function nextEpisode() { stepEpisode(1) }

  function installPackage(pkg) {
    root.statusText = "Installing " + pkg + "…"
    var cmd = "omarchy pkg aur add " + pkg
      + "; _rc=$?; printf '\\n';"
      + "if [ $_rc -ne 0 ]; then printf '\\033[1;31mInstall failed (%s).\\033[0m\\n' \"$_rc\";"
      + "else printf '\\033[1;32mInstall finished.\\033[0m\\n'; fi;"
      + "printf 'Press Enter to close.\\n'; read -r _"
    Quickshell.execDetached([
      "omarchy-launch-tui", "--app-id=TUI.float", "sh", "-c", cmd
    ])
    startDepRefresh()
  }

  function search(query) {
    var q = String(query === undefined ? searchField.text : query).trim()
    if (q === "") {
      statusText = "Type an anime name to search."
      searchField.forceActiveFocus()
      return
    }
    searchField.text = q
    browseSearch()
  }

  function continueWatching() {
    // Only block once the probe has actually finished; before that the
    // binary may exist and the launch is worth attempting.
    if (root.probeDone && !root.aniCliPresent) { open(); statusText = "ani-cli is not installed."; return }
    var args = optionArgs()
    args.push("-c")
    launch(args)
  }

  // Resume a history row: plays the saved episode immediately and opens that
  // title's episode grid (same loader as picking a search result), so the
  // grid fills in and Prev/Next steps through the full order.
  function playFromHistory(entry) {
    if (!entry || !entry.id || !entry.episode) return
    root.pendingStep = 0
    root.activeTab = 0
    root.selectedAnimeId = entry.id
    root.selectedAnimeTitle = entry.title
    // Instant playback off a stub so the saved episode starts at once…
    root.episodeList = [{ id: "", ep: entry.episode }]
    root.episodeView = root.episodeList
    root.playEpisode(entry.episode, false)
    // …while the real grid loads. A stale in-flight load is stopped first
    // so it can't overwrite this one.
    root.episodeList = []
    root.episodeView = []
    root.loadingEpisodes = true
    root.loadingEpisodesId = entry.id
    root.statusText = "Loading episodes…"
    if (episodesProc.running) episodesProc.running = false
    episodesProc.command = ["python3", root.helperPath, "episodes", entry.id]
    episodesProc.running = true
  }

  function searchEntry(entry) {
    if (!entry || !entry.title) return
    search(entry.title)
  }

  function focusSearch() {
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function refreshHistory() {
    histView.reload()
  }

  onOpenedChanged: if (opened) {
    statusText = ""
    refreshHistory()
    if (!aniSkipProbe.running) aniSkipProbe.running = true
    if (!aniCliProbe.running) aniCliProbe.running = true
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  FileView {
    id: histView
    path: root.histFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.history = root.parseHistory(text())
    onLoadFailed: root.history = []
    onFileChanged: reload()
  }

  // Probe optional companions once. `command -v` exits 1 when absent, which is
  // what onExited reports; we only care whether each binary is on PATH.
  Process {
    id: aniSkipProbe
    command: ["sh", "-c", "command -v ani-skip"]
    onExited: function(code) {
      root.aniSkipPresent = code === 0
      root.probeDone = true
    }
  }

  Process {
    id: aniCliProbe
    command: ["sh", "-c", "command -v ani-cli"]
    onExited: function(code) { root.aniCliPresent = code === 0 }
  }

  // Launches a native directory picker and records the chosen folder.
  Process {
    id: dirProbe
    command: ["zenity", "--file-selection", "--directory", "--title=Select download folder"]
    stdout: StdioCollector {
      id: dirOut
      waitForEnd: true
      onStreamFinished: {
        var p = String(dirOut.text || "").trim()
        if (p !== "") root.persistSetting("downloadDir", p)
      }
    }
  }

  // ---- native browse pipeline ----
  Process {
    id: searchProc
    stdout: StdioCollector {
      id: searchOut
      waitForEnd: true
      onStreamFinished: {
        var parsed = null
        try {
          parsed = JSON.parse(searchOut.text)
        } catch (e) {
          parsed = null
        }
        if (parsed === null) {
          root.searchResults = []
          root.statusText = "Search failed."
        } else {
          root.searchResults = parsed
          root.statusText = parsed.length === 0 ? "No results." : ""
        }
        root.searching = false
      }
    }
    stderr: StdioCollector {
      id: searchErr
      waitForEnd: true
    }
    onExited: function(code) {
      if (root.searching) root.searching = false
      if (code !== 0 && root.searchResults.length === 0 && root.statusText === "Searching…") {
        var detail = String(searchErr.text || "").trim().split("\n").pop()
        root.statusText = detail !== "" ? ("Search failed: " + detail) : ("Search failed (exit " + code + ").")
      }
    }
  }

  Process {
    id: episodesProc
    stdout: StdioCollector {
      id: episodesOut
      waitForEnd: true
      onStreamFinished: {
        // Stale arrival after navigating elsewhere: drop it so another
        // title's list never overwrites the current grid or stepping order.
        if (root.loadingEpisodesId !== "" && root.selectedAnimeId !== root.loadingEpisodesId) {
          root.loadingEpisodes = false
          root.pendingStep = 0
          root.loadingEpisodesId = ""
          return
        }
        var parsed = null
        try {
          parsed = JSON.parse(episodesOut.text)
        } catch (e) {
          parsed = null
        }
        if (parsed === null) {
          root.episodeList = []
          root.refreshEpisodeView()
          root.loadingEpisodes = false
          root.loadingEpisodesId = ""
          root.pendingStep = 0
          root.statusText = "Failed to load episodes."
          return
        }
        root.episodeList = parsed
        root.refreshEpisodeView()
        root.loadingEpisodes = false
        root.loadingEpisodesId = ""
        var playbackActive = root.playingEpisode
          || root.statusText === "Resolving stream…"
          || String(root.statusText).indexOf("Playing ") === 0
        // The grid caught up with the now-playing title (e.g. a history
        // resume opened it): upgrade Prev/Next to the full order.
        if (root.selectedAnimeId === root.nowPlayingAnimeId && root.nowPlayingAnimeId !== "" && root.nowPlayingEp !== "") {
          root.nowPlayingEpisodes = root.episodeList.slice()
          root.nowPlayingFullList = true
        }
        // A queued Prev/Next step only applies when this list belongs to the
        // now-playing title; otherwise it is stale and dropped.
        if (root.pendingStep !== 0 && root.selectedAnimeId === root.nowPlayingAnimeId && root.nowPlayingAnimeId !== "") {
          var d = root.pendingStep
          root.pendingStep = 0
          if (root.episodeList.length === 0) {
            root.statusText = "No episodes found."
            return
          }
          root.nowPlayingEpisodes = root.episodeList.slice()
          root.nowPlayingFullList = true
          root.statusText = ""
          root.applyStep(d)
          return
        }
        root.pendingStep = 0
        // While a stream is resolving/playing, leave its status alone.
        if (!playbackActive) root.statusText = root.episodeList.length === 0 ? "No episodes found." : ""
      }
    }
    stderr: StdioCollector {
      id: episodesErr
      waitForEnd: true
    }
    onExited: function(code) {
      if (root.loadingEpisodesId !== "" && root.selectedAnimeId !== root.loadingEpisodesId) {
        root.loadingEpisodes = false
        root.pendingStep = 0
        root.loadingEpisodesId = ""
        return
      }
      if (root.loadingEpisodes) root.loadingEpisodes = false
      if (code !== 0 && root.episodeList.length === 0 && root.statusText === "Loading episodes…") {
        var detail = String(episodesErr.text || "").trim().split("\n").pop()
        root.pendingStep = 0
        root.loadingEpisodesId = ""
        root.statusText = detail !== "" ? ("Failed to load episodes: " + detail) : ("Failed to load episodes (exit " + code + ").")
      }
    }
  }

  Process {
    id: playProc
    stdout: StdioCollector {
      id: playOut
      waitForEnd: true
      onStreamFinished: {
        var info
        try {
          info = JSON.parse(playOut.text)
        } catch (e) {
          var errDetail = String(playErr.text || "").trim().split("\n").pop()
          root.statusText = errDetail !== "" ? ("Failed to resolve stream: " + errDetail) : "Failed to resolve stream."
          root.playingEpisode = false
          return
        }
        root.playingEpisode = false
        if (!info || !info.video_link) {
          root.statusText = (info && (info.error || info.stderr)) ? (info.error || info.stderr) : "No playable source."
          return
        }
        var mediaTitle = root.selectedAnimeTitle + (root.currentPlayEp ? " Episode " + root.currentPlayEp : "")
        var scriptArgs = [info.video_link, info.refr || "", info.sub_link || "", mediaTitle]
        Quickshell.execDetached(["sh", root.playerPath].concat(scriptArgs))
        if (root.selectedAnimeId && root.currentPlayEp) {
          Quickshell.execDetached(["sh", root.historyPath, root.currentPlayEp, root.selectedAnimeId, root.selectedAnimeTitle])
          Qt.callLater(function() { histView.reload() })
        }
        root.statusText = "Playing " + mediaTitle + "…"
      }
    }
    stderr: StdioCollector {
      id: playErr
      waitForEnd: true
    }
    onExited: function(code) {
      if (root.playingEpisode) root.playingEpisode = false
      if (code !== 0 && root.statusText === "Resolving stream…") {
        var detail = String(playErr.text || "").trim().split("\n").pop()
        root.statusText = detail !== "" ? ("Failed to resolve stream: " + detail) : ("Failed to resolve stream (exit " + code + ").")
      }
    }
  }

  Component.onCompleted: {
    aniSkipProbe.running = true
    aniCliProbe.running = true
  }

  // Re-probe in the background after an install launch, until both helpers show
  // up (capped so we don't leave a timer behind a permanently-missing package).
  Timer {
    id: depRefresh
    interval: 3000
    repeat: true
    running: false
    onTriggered: {
      root.depRefreshAttempts++
      if ((root.aniSkipPresent && root.aniCliPresent) || root.depRefreshAttempts >= 20) {
        depRefresh.stop()
        root.depRefreshAttempts = 0
        return
      }
      if (!aniSkipProbe.running) aniSkipProbe.running = true
      if (!aniCliProbe.running) aniCliProbe.running = true
    }
  }

  IpcHandler {
    target: "animarchy"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function search(): void { root.open(); root.focusSearch() }
    function continueWatching(): void { root.continueWatching() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    // No single-key shortcuts: this panel is click-driven (toggles live in
    // Settings). Esc closes and Tab moves between panels, which are Omarchy
    // shell conventions, not plugin shortcuts.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || downloadDirField.activeFocus || episodeRangeField.activeFocus || qualityDropdown.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroller.width
          spacing: Style.space(10)

          // ---- header ----
          RowLayout {
            width: parent.width

            Text {
              Layout.alignment: Qt.AlignVCenter
              text: "\uf26c"
              color: Color.accent
              font.family: root.ff
              font.pixelSize: Style.font.iconLarge
            }

            Column {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              leftPadding: Style.space(10)
              spacing: Style.space(1)

              Text {
                text: "animarchy"
                color: root.fg
                font.family: root.ff
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: root.downloadEnabled ? "DOWNLOAD MODE" : "STREAM MODE"
                color: root.dim
                font.family: root.ff
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }

            Button {
              text: root.showSettings ? "✕" : "⚙"
              foreground: root.fg
              focusable: true
              fontSize: Style.font.iconLarge
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(4)
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              tooltipText: root.showSettings ? "Back" : "Settings"
              onClicked: root.showSettings = !root.showSettings
            }
          }

          PanelSeparator { width: parent.width }

          Column {
            visible: !root.aniCliPresent
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: "ani-cli is not installed. Search, playback, and history need it."
              color: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Button {
              text: "Install ani-cli"
              iconText: "\uf019"
              foreground: root.fg
              onClicked: root.installPackage("ani-cli")
            }
          }

          TextField {
            id: searchField
            visible: !root.showSettings
            width: parent.width
            placeholderText: "Search anime…"
            foreground: root.fg
            onAccepted: root.browseSearch()
            Keys.onEscapePressed: root.close()
            Keys.onDownPressed: keyCatcher.forceActiveFocus()
          }

          Row {
            visible: !root.showSettings
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: root.activeTab === 0 ? "● Search" : "Search"
              foreground: root.activeTab === 0 ? Color.accent : root.fg
              focusable: true
              width: (parent.width - parent.spacing) / 2
              onClicked: root.activeTab = 0
            }

            Button {
              text: root.activeTab === 1 ? "● Play History" : "Play History"
              foreground: root.activeTab === 1 ? Color.accent : root.fg
              focusable: true
              width: (parent.width - parent.spacing) / 2
              onClicked: root.activeTab = 1
            }
          }

          // ---- search ----
          Text {
            visible: root.activeTab === 0 && !root.showSettings && root.searchResults.length > 0 && root.selectedAnimeId === ""
            text: root.searchResults.length + " result(s)"
            color: root.dim
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }

          ListView {
            id: resultsView
            visible: root.activeTab === 0 && !root.showSettings && root.searchResults.length > 0 && root.selectedAnimeId === "" && !root.searching
            width: parent.width
            height: Math.min(root.searchResults.length * 40, 280)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.searchResults
            spacing: Style.space(4)

            delegate: Button {
              text: modelData.title
              width: resultsView.width
              leftAlign: true
              foreground: root.fg
              onClicked: root.selectAnime(modelData.id, modelData.title)
            }
          }

          // selected show: episode grid
          Column {
            visible: root.activeTab === 0 && !root.showSettings && root.selectedAnimeId !== ""
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width

              Button {
                text: "← Back"
                foreground: root.fg
                onClicked: root.clearSelection()
              }

              Text {
                text: root.selectedAnimeTitle
                color: root.fg
                font.family: root.ff
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: Style.space(10)
                elide: Text.ElideRight
                width: parent.width - 110
              }
            }

            Text {
              visible: root.loadingEpisodes
              text: "Loading episodes…"
              color: root.dim
              font.family: root.ff
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: root.episodeView.length > 0 && root.episodeView.length < root.episodeList.length && !root.loadingEpisodes
              text: "Showing " + root.episodeView.length + " of " + root.episodeList.length + " episodes"
              color: root.dim
              font.family: root.ff
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: root.episodeList.length > 0 && root.episodeView.length === 0 && !root.loadingEpisodes
              text: "No episodes match \"" + root.episodeRange.trim() + "\""
              color: root.dim
              font.family: root.ff
              font.pixelSize: Style.font.caption
            }

            GridView {
              id: episodeGrid
              visible: root.episodeView.length > 0 && !root.loadingEpisodes
              width: parent.width
              height: Math.min(Math.ceil(root.episodeView.length / 8) * 34, 240)
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              cellWidth: parent.width / 8
              cellHeight: 34
              model: root.episodeView

              delegate: Rectangle {
                width: episodeGrid.cellWidth
                height: episodeGrid.cellHeight
                color: "transparent"

                BorderSurface {
                  anchors.fill: parent
                  anchors.margins: 2
                  color: "transparent"
                  borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
                  radius: Style.cornerRadius

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "EP " + modelData.ep
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.playEpisode(modelData.ep, true)
                  }
                }
              }
            }

            Button {
              visible: root.episodeView.length > 0 && !root.loadingEpisodes
              width: parent.width
              leftAlign: true
              text: "Download " + (root.episodeView.length === root.episodeList.length ? "all " : "") + root.episodeView.length + " episode" + (root.episodeView.length === 1 ? "" : "s")
              iconText: "󰁯"
              foreground: root.fg
              onClicked: root.downloadEpisodes()
            }
          }

          PanelSeparator {
            width: parent.width
            visible: root.activeTab === 0 && !root.showSettings
          }

          Column {
            visible: root.showSettings
            width: parent.width
            spacing: Style.space(10)

          // ---- options ----
          Text {
            text: "OPTIONS"
            color: root.dim
            font.family: root.ff
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Toggle {
                id: dubToggle
                label: "English dub"
                description: "Dubbed track; falls back to sub when no dub source"
                width: (parent.width - parent.spacing) / 2
                height: Math.max(dubToggle.implicitHeight, dlToggle.implicitHeight)
                checked: root.dubEnabled
                foreground: root.fg
                onClicked: root.persistSetting("dub", !root.dubEnabled)
              }

              Toggle {
                id: dlToggle
                label: "Download"
                description: "Save to disk instead of streaming"
                width: (parent.width - parent.spacing) / 2
                height: Math.max(dubToggle.implicitHeight, dlToggle.implicitHeight)
                checked: root.downloadEnabled
                foreground: root.fg
                onClicked: root.persistSetting("download", !root.downloadEnabled)
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Toggle {
                id: skipToggle
                label: "Skip intro"
                description: root.aniSkipPresent
                  ? "Needs ani-skip · mpv only"
                  : "Unavailable · install ani-skip"
                width: (parent.width - parent.spacing) / 2
                height: Math.max(skipToggle.implicitHeight, nxToggle.implicitHeight)
                checked: root.skipIntroEnabled && root.aniSkipPresent
                enabled: root.aniSkipPresent
                opacity: root.aniSkipPresent ? 1 : 0.5
                foreground: root.fg
                onClicked: root.persistSetting("skipIntro", !root.skipIntroEnabled)
              }

              Toggle {
                id: nxToggle
                label: "Next-ep countdown"
                description: "Show time until next release"
                width: (parent.width - parent.spacing) / 2
                height: Math.max(skipToggle.implicitHeight, nxToggle.implicitHeight)
                checked: root.nextepEnabled
                foreground: root.fg
                onClicked: root.persistSetting("nextep", !root.nextepEnabled)
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(3)

            Text {
              text: "Download folder"
              color: root.dim
              font.family: root.ff
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: downloadDirField
                width: parent.width - 110 - parent.spacing
                placeholderText: "e.g. ~/Downloads"
                text: root.downloadDir
                foreground: root.fg
                onEditingFinished: if (text !== root.downloadDir) root.persistSetting("downloadDir", text)
                onAccepted: {
                  if (text !== root.downloadDir) root.persistSetting("downloadDir", text)
                  root.close()
                }
              }

              Button {
                text: "Browse…"
                foreground: root.fg
                width: 110
                onClicked: dirProbe.running = true
              }
            }
          }

          // One-click install for the optional AUR packages. Each opens a
          // floating terminal so the (interactive, sudo) process is readable,
          // then we re-probe until the binary shows up.
          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.aniSkipPresent

            Button {
              id: installSkipBtn
              visible: !root.aniSkipPresent
              text: "Install ani-skip"
              iconText: "\uf019"
              foreground: root.fg
              onClicked: root.installPackage("ani-skip")
            }

          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Column {
              width: (parent.width - parent.spacing) * 0.5
              spacing: Style.space(3)

              Text {
                text: "Quality"
                color: root.dim
                font.family: root.ff
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Dropdown {
                id: qualityDropdown
                width: parent.width
                showLabel: false
                value: root.quality
                options: ["best", "worst", "1080", "720", "480", "360"]
                onChanged: function(v) { root.persistSetting("quality", v) }
              }
            }

            Column {
              width: (parent.width - parent.spacing) * 0.5
              spacing: Style.space(3)

              Text {
                text: "Episodes (blank = pick in terminal)"
                color: root.dim
                font.family: root.ff
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              TextField {
                id: episodeRangeField
                width: parent.width
                placeholderText: "e.g. 1-12"
                text: root.episodeRange
                foreground: root.fg
                Keys.onEscapePressed: root.close()
                onEditingFinished: { if (text !== root.episodeRange) root.persistSetting("episodes", text); root.refreshEpisodeView() }
                onAccepted: {
                  if (text !== root.episodeRange) root.persistSetting("episodes", text)
                  root.refreshEpisodeView()
                  root.search()
                }
              }
            }
          }
          }

          PanelSeparator {
            width: parent.width
            visible: root.activeTab === 1 && !root.showSettings && root.history.length > 0
          }

          // ---- history ----
          Text {
            visible: root.activeTab === 1 && !root.showSettings && root.history.length > 0
            text: "RECENT"
            color: root.dim
            font.family: root.ff
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          Column {
            visible: root.activeTab === 1 && !root.showSettings
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.history.slice(0, root.historyLimit)

            delegate: Rectangle {
              required property var modelData
              width: content.width
              implicitHeight: 32
              color: "transparent"

              Button {
                id: rowContent
                anchors.fill: parent
                text: ""
                foreground: root.fg
                onClicked: root.playFromHistory(modelData)
              }

              Item {
                id: titleItem
                clip: true
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12 + 32 + 6 + (episodePill.visible ? episodePill.implicitWidth + 6 : 0))
                anchors.verticalCenter: parent.verticalCenter
                height: titleRow.implicitHeight

                Row {
                  id: titleRow
                  spacing: Style.space(24)
                  x: 0

                  Text {
                    id: titleTextA
                    text: modelData.title
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                  }
                  // Duplicate copy only rendered while the marquee can run;
                  // otherwise short titles would show twice ("Bleach Bleach").
                  Text {
                    visible: titleTextA.implicitWidth > titleItem.width
                    text: modelData.title
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.body
                  }

                  Timer {
                    id: marqueeTimer
                    interval: 50
                    repeat: true
                    running: root.activeTab === 1 && !root.showSettings && titleTextA.implicitWidth > titleItem.width && !rowContent.hot
                    onTriggered: {
                      var shift = titleTextA.implicitWidth + titleRow.spacing
                      titleRow.x -= 1
                      if (titleRow.x <= -shift) titleRow.x += shift
                    }
                  }
                }
              }

              BorderSurface {
                id: episodePill
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                visible: String(modelData.episode) !== ""
                implicitWidth: epText.implicitWidth + Style.space(10)
                implicitHeight: epText.implicitHeight + Style.space(4)
                color: "transparent"
                borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
                radius: Style.cornerRadius

                Text {
                  id: epText
                  anchors.centerIn: parent
                  text: "EP " + modelData.episode
                  color: root.dim
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Button {
                text: "☰"
                foreground: root.fg
                width: 32
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12 + episodePill.implicitWidth + 6)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: {
                  root.activeTab = 0
                  root.pendingStep = 0
                  root.selectedAnimeId = modelData.id
                  root.selectedAnimeTitle = modelData.title
                  root.episodeList = []
                  root.loadingEpisodes = true
                  root.loadingEpisodesId = modelData.id
                  root.statusText = "Loading episodes…"
                  if (episodesProc.running) episodesProc.running = false
                  episodesProc.command = ["python3", root.helperPath, "episodes", modelData.id]
                  episodesProc.running = true
                }
              }
            }
          }

            Text {
              visible: root.history.length === 0
              width: parent.width
              text: "No watch history yet."
              color: root.dim
              font.family: root.ff
              font.pixelSize: Style.font.body
            }
          }

          Text {
            visible: root.statusText !== ""
            width: parent.width
            text: root.statusText
            color: Color.accent
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }

          // ---- now playing footer ----
          Column {
            visible: root.nowPlayingEp !== ""
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { width: parent.width }

            RowLayout {
              width: parent.width

              Text {
                text: root.nowPlayingTitle
                color: root.fg
                font.family: root.ff
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Text {
                text: "EP " + root.nowPlayingEp
                color: root.dim
                font.family: root.ff
                font.pixelSize: Style.font.subtitle
                font.bold: true
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "⏮ Prev"
                foreground: root.fg
                width: (parent.width - parent.spacing) / 2
                // Disabled while a stream is resolving: the helper runs one
                // lookup at a time, so clicks then would be swallowed.
                enabled: !root.playingEpisode
                opacity: root.playingEpisode ? 0.5 : 1
                onClicked: root.prevEpisode()
              }

              Button {
                text: "Next ⏭"
                foreground: root.fg
                width: (parent.width - parent.spacing) / 2
                enabled: !root.playingEpisode
                opacity: root.playingEpisode ? 0.5 : 1
                onClicked: root.nextEpisode()
              }
            }
          }
        }
      }
    }
  }
}