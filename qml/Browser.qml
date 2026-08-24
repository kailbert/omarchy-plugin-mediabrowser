import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "BrowserModel.js" as BrowserModel

BorderSurface {
  id: root

  property var backend: null
  property string openPath: ""
  property string currentDirectory: ""
  property var entries: []
  property var pendingEntries: []
  property var rows: []
  property var places: []
  property var backHistory: []
  property var forwardHistory: []
  property int directorySerial: 0
  property int selectedIndex: 0
  property string selectedPath: ""
  property string filterText: ""
  property string sortMode: "name"
  property bool sortDescending: false
  property bool foldersFirst: true
  property bool showHidden: false
  property real thumbnailWidth: Style.space(230)
  property real gapSize: Style.spacing.md
  property real sidebarWidth: Style.space(205)
  property bool sidebarVisible: true
  property bool showLabels: true
  property bool fullscreenActive: false
  property bool loading: false
  property bool enumerationDone: false
  property string statusMessage: ""
  property string deferredPath: ""
  property var thumbPending: ({})
  property var thumbFailed: ({})
  property bool contextOpen: false
  property real contextX: 0
  property real contextY: 0
  property bool renameOpen: false
  property bool trashOpen: false
  property bool sortOpen: false
  property bool locationOpen: false
  property bool searchOpen: false
  property bool settingsOpen: false
  property bool helpOpen: false
  property string pendingVimKey: ""
  property var actionRow: null
  readonly property real effectiveSidebarWidth: sidebarVisible ? Math.max(Style.space(150), Math.min(Style.space(320), sidebarWidth)) : 0
  readonly property string homePath: Quickshell.env("HOME")
  readonly property var selectedRow: selectedIndex >= 0 && selectedIndex < rows.length ? rows[selectedIndex] : null

  signal dismissRequested()
  signal watchRequested(string path)
  signal fullscreenToggleRequested()

  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.normalBorderWidth))
  radius: Style.cornerRadius
  clip: true

  function activate() {
    keyCatcher.forceActiveFocus()
    if (backend && backend.backendReady) {
      if (openPath) {
        var requested = openPath
        openPath = ""
        navigate(requested, currentDirectory !== "")
      } else initialNavigate()
    }
  }

  function deactivate() {
    quickLook.close()
    saveState()
    contextOpen = false
    renameOpen = false
    trashOpen = false
  }

  function initialNavigate() {
    if (openPath) {
      var requested = openPath
      openPath = ""
      navigate(requested, currentDirectory !== "")
      return
    }
    if (currentDirectory) { refresh(false); return }
    var target = deferredPath || homePath
    navigate(target, false)
  }

  function navigate(path, recordHistory) {
    var target = String(path || "")
    if (!target || !backend || !backend.backendReady) { deferredPath = target; return }
    // Filters are directory-local. Keeping one while navigating makes a
    // populated destination look empty and hides why it happened.
    filterText = ""
    searchOpen = false
    if (recordHistory !== false && currentDirectory && currentDirectory !== target) {
      backHistory = backHistory.concat([currentDirectory])
      forwardHistory = []
    }
    directorySerial++
    pendingEntries = []
    entries = []
    thumbFailed = ({})
    rows = []
    selectedIndex = 0
    selectedPath = ""
    loading = true
    enumerationDone = false
    statusMessage = ""
    contextOpen = false
    backend.send({command: "list", serial: directorySerial, path: target, hidden: showHidden})
  }

  function refresh(preserveSelection) {
    if (!currentDirectory) return
    if (preserveSelection !== false && selectedRow) selectedPath = selectedRow.path
    directorySerial++
    pendingEntries = []
    entries = []
    thumbFailed = ({})
    loading = true
    enumerationDone = false
    statusMessage = ""
    backend.send({command: "list", serial: directorySerial, path: currentDirectory, hidden: showHidden})
  }

  function externalChange() { refreshDebounce.restart() }

  function goBack() {
    if (!backHistory.length) return
    var target = backHistory[backHistory.length - 1]
    backHistory = backHistory.slice(0, -1)
    if (currentDirectory) forwardHistory = [currentDirectory].concat(forwardHistory)
    navigate(target, false)
  }

  function goForward() {
    if (!forwardHistory.length) return
    var target = forwardHistory[0]
    forwardHistory = forwardHistory.slice(1)
    if (currentDirectory) backHistory = backHistory.concat([currentDirectory])
    navigate(target, false)
  }

  function goParent() { navigate(BrowserModel.parentPath(currentDirectory), true) }

  function openDirectoryFinder() {
    var rootPath = currentDirectory.indexOf(homePath + "/") === 0 || currentDirectory === homePath
      ? homePath : currentDirectory
    directoryFinder.show(rootPath)
  }

  function handleMessage(message) {
    if (message.event === "ready") {
      places = message.places || []
      var state = message.state || {}
      if (state.thumbnailWidth) thumbnailWidth = Math.max(Style.space(150), Math.min(Style.space(380), Number(state.thumbnailWidth)))
      if (state.gapSize !== undefined) gapSize = Math.max(Style.space(2), Math.min(Style.space(32), Number(state.gapSize)))
      if (state.sidebarWidth) sidebarWidth = Math.max(Style.space(150), Math.min(Style.space(320), Number(state.sidebarWidth)))
      if (state.sidebarVisible !== undefined) sidebarVisible = state.sidebarVisible === true
      if (state.showLabels !== undefined) showLabels = state.showLabels === true
      if (state.foldersFirst !== undefined) foldersFirst = state.foldersFirst === true
      if (state.sortMode) sortMode = String(state.sortMode)
      sortDescending = state.sortDescending === true
      showHidden = state.showHidden === true
      deferredPath = String(state.lastDirectory || "")
      initialNavigate()
    } else if (message.serial === directorySerial && message.event === "begin") {
      currentDirectory = String(message.path)
      deferredPath = ""
      watchRequested(currentDirectory)
    } else if (message.serial === directorySerial && message.event === "entry") {
      pendingEntries.push(message)
      batchTimer.restart()
    } else if (message.serial === directorySerial && message.event === "end") {
      flushPending()
      loading = false
      enumerationDone = true
      saveState()
    } else if (message.serial === directorySerial && message.event === "error" && message.operation === "list") {
      loading = false
      enumerationDone = true
      statusMessage = message.message || "Unable to read folder"
    } else if (message.event === "thumbnail" || message.event === "thumbnail-error") {
      var nextPending = ({})
      for (var key in thumbPending) if (key !== message.requestId) nextPending[key] = thumbPending[key]
      thumbPending = nextPending
      if (message.event === "thumbnail") applyThumbnail(message)
      else markThumbnailFailed(message.path)
    } else if (message.event === "error" && message.operation === "backend") {
      statusMessage = message.message || "File helper unavailable"
    } else if (message.event === "action") {
      if (!message.ok) toast(message.message || "Action failed")
      else if (message.operation === "rename") { renameOpen = false; refresh(false); toast("Renamed") }
    }
  }

  function flushPending() {
    if (!pendingEntries.length) return
    entries = entries.concat(pendingEntries)
    pendingEntries = []
    rebuildTimer.restart()
  }

  function rebuildRows() {
    var keep = selectedRow ? selectedRow.path : selectedPath
    rows = BrowserModel.displayRows(entries, filterText, sortMode, sortDescending, foldersFirst)
    var found = -1
    if (keep) for (var i = 0; i < rows.length; i++) if (rows[i].path === keep) { found = i; break }
    selectedIndex = rows.length ? (found >= 0 ? found : Math.max(0, Math.min(selectedIndex, rows.length - 1))) : 0
    selectedPath = rows.length ? rows[selectedIndex].path : ""
    Qt.callLater(function() { masonry.ensureVisible(root.selectedIndex) })
  }

  function applyThumbnail(message) {
    var changed = false
    var copy = entries.slice()
    for (var i = 0; i < copy.length; i++) {
      if (copy[i].path !== message.path) continue
      var row = Object.assign({}, copy[i])
      row.thumbnail = message.thumbnail || row.thumbnail
      row.aspect = Number(message.aspect || row.aspect)
      row.duration = Number(message.duration || row.duration)
      row.width = Number(message.width || 0)
      row.height = Number(message.height || 0)
      copy[i] = row
      changed = true
      break
    }
    if (changed) { entries = copy; rebuildTimer.restart() }
  }

  function requestThumbnail(path, kind) {
    if (thumbFailed[path] === true) return
    for (var id in thumbPending) if (thumbPending[id] === path) return
    var requestId = backend.nextRequestId("thumb")
    var next = ({})
    for (var key in thumbPending) next[key] = thumbPending[key]
    next[requestId] = path
    thumbPending = next
    backend.send({command: "thumbnail", requestId: requestId, path: path, kind: kind, width: 640})
  }

  function markThumbnailFailed(path) {
    var failed = ({})
    for (var key in thumbFailed) failed[key] = thumbFailed[key]
    failed[String(path || "")] = true
    thumbFailed = failed
    var copy = entries.slice()
    for (var i = 0; i < copy.length; i++) {
      if (copy[i].path !== path) continue
      var row = Object.assign({}, copy[i])
      row.broken = true
      copy[i] = row
      entries = copy
      rebuildTimer.restart()
      break
    }
  }

  function select(index) {
    if (!rows.length) return
    selectedIndex = Math.max(0, Math.min(index, rows.length - 1))
    selectedPath = rows[selectedIndex].path
    masonry.ensureVisible(selectedIndex)
    contextOpen = false
  }

  function moveHorizontal(delta) { select(selectedIndex + delta) }

  function moveVertical(delta) {
    if (!masonry.layoutRows.length || selectedIndex >= masonry.layoutRows.length) return
    var current = masonry.layoutRows[selectedIndex]
    var best = -1, score = Number.MAX_VALUE
    var cx = current.x + current.width / 2
    var cy = current.y + current.height / 2
    for (var i = 0; i < masonry.layoutRows.length; i++) {
      if (i === selectedIndex) continue
      var candidate = masonry.layoutRows[i]
      var tx = candidate.x + candidate.width / 2
      var ty = candidate.y + candidate.height / 2
      var dy = ty - cy
      if ((delta < 0 && dy >= -1) || (delta > 0 && dy <= 1)) continue
      var scoreNow = Math.abs(dy) + Math.abs(tx - cx) * 1.7
      if (scoreNow < score) { score = scoreNow; best = i }
    }
    if (best >= 0) select(best)
  }

  function activateSelected() {
    if (!selectedRow) return
    if (selectedRow.kind === "folder") navigate(selectedRow.path, true)
    else if (selectedRow.kind === "image" || selectedRow.kind === "video") quickLook.show(selectedIndex)
    else openDefault(selectedRow)
  }

  function openDefault(row) {
    if (!row) return
    Quickshell.execDetached(["xdg-open", row.path])
    toast("Opened in default application")
  }

  function copyPath(row) {
    if (!row) return
    Quickshell.execDetached(["wl-copy", row.path])
    contextOpen = false
    toast("Path copied")
  }

  function beginRename(row) {
    if (!row) return
    actionRow = row
    renameField.text = row.name
    renameOpen = true
    contextOpen = false
    Qt.callLater(function() { renameField.forceActiveFocus(); renameField.selectAll() })
  }

  function commitRename() {
    if (!actionRow || !renameField.text || renameField.text === actionRow.name) { renameOpen = false; keyCatcher.forceActiveFocus(); return }
    backend.send({command: "action", operation: "rename", requestId: backend.nextRequestId("rename"), path: actionRow.path, name: renameField.text})
  }

  function requestTrash(row) {
    if (!row) return
    actionRow = row
    trashDialog.message = "Move “" + row.name + "” to Trash?"
    trashOpen = true
    contextOpen = false
  }

  function confirmTrash() {
    if (!actionRow) return
    trashProc.command = ["gio", "trash", "--", actionRow.path]
    trashProc.running = true
    trashOpen = false
  }

  function showContext(index, sceneX, sceneY) {
    select(index)
    actionRow = rows[index]
    var local = root.mapFromItem(null, sceneX, sceneY)
    contextX = Math.max(Style.space(8), Math.min(width - Style.space(190), local.x))
    contextY = Math.max(Style.space(8), Math.min(height - Style.space(190), local.y))
    contextOpen = true
  }

  function toast(message) {
    statusMessage = message
    toastTimer.restart()
  }

  function saveState() {
    if (!backend || !backend.backendReady || !currentDirectory) return
    backend.send({command: "action", operation: "state", requestId: backend.nextRequestId("state"), value: {
      lastDirectory: currentDirectory, thumbnailWidth: thumbnailWidth, sortMode: sortMode,
      gapSize: gapSize, sidebarWidth: sidebarWidth, sidebarVisible: sidebarVisible, showLabels: showLabels,
      foldersFirst: foldersFirst, sortDescending: sortDescending, showHidden: showHidden
    }})
  }

  function resetAppearance() {
    thumbnailWidth = Style.space(230)
    gapSize = Style.spacing.md
    sidebarWidth = Style.space(205)
    sidebarVisible = true
    showLabels = true
    foldersFirst = true
    saveState()
  }

  function crumbRows() {
    if (!currentDirectory || currentDirectory === "/") return [{label: "/", path: "/"}]
    var parts = currentDirectory.split("/").filter(function(x) { return x.length > 0 })
    var result = [{label: "󰋜", path: "/"}], path = ""
    for (var i = 0; i < parts.length; i++) { path += "/" + parts[i]; result.push({label: parts[i], path: path}) }
    return result
  }

  Connections { target: root.backend; function onHelperMessage(message) { root.handleMessage(message) } }

  Timer { id: batchTimer; interval: 45; onTriggered: root.flushPending() }
  Timer { id: rebuildTimer; interval: 38; onTriggered: root.rebuildRows() }
  Timer { id: refreshDebounce; interval: 240; onTriggered: root.refresh(true) }
  Timer { id: toastTimer; interval: 2200; onTriggered: root.statusMessage = "" }
  Timer { id: vimChordTimer; interval: 700; onTriggered: root.pendingVimKey = "" }

  Process {
    id: trashProc
    onExited: function(exitCode) {
      if (exitCode === 0) { root.toast("Moved to Trash"); root.refresh(false) }
      else root.toast("Could not move item to Trash")
      keyCatcher.forceActiveFocus()
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (root.renameOpen || root.trashOpen) {
        if (root.trashOpen && trashDialog.handleKey(event)) event.accepted = true
        return
      }
      if (root.helpOpen) {
        if (event.key === Qt.Key_Escape || event.text === "?") root.helpOpen = false
        event.accepted = true
        return
      }
      if (root.settingsOpen && event.key === Qt.Key_Escape) {
        root.settingsOpen = false
        event.accepted = true
        return
      }
      if (quickLook.opened) {
        var shifted = (event.modifiers & Qt.ShiftModifier) !== 0
        if (event.key === Qt.Key_Escape || event.text === "q") quickLook.close()
        else if (event.text === "?") root.helpOpen = true
        else if (event.text === "c" || event.key === Qt.Key_Tab) quickLook.toggleControls()
        else if (event.key === Qt.Key_BracketLeft || (shifted && event.key === Qt.Key_Left)) quickLook.move(-1)
        else if (event.key === Qt.Key_BracketRight || (shifted && event.key === Qt.Key_Right)) quickLook.move(1)
        else if (event.key === Qt.Key_Space) quickLook.togglePlayback()
        else if (quickLook.isVideo && (event.key === Qt.Key_Left || event.text === "h")) quickLook.seekRelative(-5000)
        else if (quickLook.isVideo && (event.key === Qt.Key_Right || event.text === "l")) quickLook.seekRelative(5000)
        else if (quickLook.isVideo && event.text === "j") quickLook.seekRelative(-10000)
        else if (quickLook.isVideo && event.text === "k") quickLook.togglePlayback()
        else if (quickLook.isVideo && event.text === "m") quickLook.toggleMute()
        else if (!quickLook.isVideo && (event.key === Qt.Key_Left || event.text === "h")) quickLook.move(-1)
        else if (!quickLook.isVideo && (event.key === Qt.Key_Right || event.text === "l")) quickLook.move(1)
        else if (!quickLook.isVideo && (event.text === "f" || event.text === "0")) quickLook.fitImage()
        else if (!quickLook.isVideo && event.text === "1") quickLook.actualSize()
        else if (!quickLook.isVideo && (event.text === "+" || event.text === "=")) quickLook.adjustZoom(1.25)
        else if (!quickLook.isVideo && event.text === "-") quickLook.adjustZoom(0.8)
        else return
        event.accepted = true; return
      }
      var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
      var alt = (event.modifiers & Qt.AltModifier) !== 0
      var shiftedBrowser = (event.modifiers & Qt.ShiftModifier) !== 0
      if (root.pendingVimKey === "g") {
        root.pendingVimKey = ""
        vimChordTimer.stop()
        if (event.text === "g") root.select(0)
        else if (event.text === "h") root.navigate(root.homePath, true)
        else if (event.text === "p") {
          for (var pi = 0; pi < root.places.length; pi++) if (root.places[pi].name === "Pictures") { root.navigate(root.places[pi].path, true); break }
        } else return
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Escape) {
        if (root.contextOpen || root.sortOpen || root.settingsOpen) { root.contextOpen = false; root.sortOpen = false; root.settingsOpen = false }
        else if (root.searchOpen || root.filterText) { root.searchOpen = false; root.filterText = ""; rebuildTimer.restart() }
        else root.dismissRequested()
      } else if (event.key === Qt.Key_F11) {
        root.fullscreenToggleRequested()
      } else if (ctrl && event.key === Qt.Key_L) {
        root.locationOpen = true; locationField.text = root.currentDirectory
        Qt.callLater(function() { locationField.forceActiveFocus(); locationField.selectAll() })
      } else if (ctrl && event.key === Qt.Key_F || event.key === Qt.Key_Slash) {
        root.searchOpen = true; Qt.callLater(function() { searchField.forceActiveFocus() })
      } else if (ctrl && event.key === Qt.Key_H) {
        root.showHidden = !root.showHidden; root.refresh(true); root.toast(root.showHidden ? "Hidden files shown" : "Hidden files hidden")
      } else if (shiftedBrowser && (event.key === Qt.Key_Plus || event.text === "+" || event.text === "*")) {
        root.gapSize = Math.min(Style.space(32), root.gapSize + Style.space(2)); root.saveState(); root.toast("Grid gap " + Math.round(root.gapSize) + " px")
      } else if (shiftedBrowser && (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore || event.text === "_")) {
        root.gapSize = Math.max(Style.space(2), root.gapSize - Style.space(2)); root.saveState(); root.toast("Grid gap " + Math.round(root.gapSize) + " px")
      } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.text === "+" || event.text === "=") {
        root.thumbnailWidth = Math.min(Style.space(420), root.thumbnailWidth + Style.space(10)); root.saveState(); root.toast("Thumbnails " + Math.round(root.thumbnailWidth) + " px")
      } else if (event.key === Qt.Key_Minus || event.text === "-") {
        root.thumbnailWidth = Math.max(Style.space(140), root.thumbnailWidth - Style.space(10)); root.saveState(); root.toast("Thumbnails " + Math.round(root.thumbnailWidth) + " px")
      } else if (ctrl && event.key === Qt.Key_D) {
        masonry.page(.5)
      } else if (ctrl && event.key === Qt.Key_U) {
        masonry.page(-.5)
      } else if (alt && event.key === Qt.Key_Left) root.goBack()
      else if (alt && event.key === Qt.Key_Right) root.goForward()
      else if (event.key === Qt.Key_Backspace) root.goParent()
      else if (event.key === Qt.Key_Left || event.text === "h") root.moveHorizontal(-1)
      else if (event.key === Qt.Key_Right || event.text === "l") root.moveHorizontal(1)
      else if (event.key === Qt.Key_Up || event.text === "k") root.moveVertical(-1)
      else if (event.key === Qt.Key_Down || event.text === "j") root.moveVertical(1)
      else if (event.key === Qt.Key_PageUp) { masonry.page(-1); root.moveVertical(-1) }
      else if (event.key === Qt.Key_PageDown) { masonry.page(1); root.moveVertical(1) }
      else if (event.key === Qt.Key_Home) root.select(0)
      else if (event.key === Qt.Key_End || event.text === "G") root.select(root.rows.length - 1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.text === "o") root.activateSelected()
      else if (event.key === Qt.Key_Space) { if (root.selectedRow && (root.selectedRow.kind === "image" || root.selectedRow.kind === "video")) quickLook.show(root.selectedIndex) }
      else if (event.key === Qt.Key_F2) root.beginRename(root.selectedRow)
      else if (event.text === "g") { root.pendingVimKey = "g"; vimChordTimer.restart() }
      else if (event.text === "H") root.goBack()
      else if (event.text === "L") root.goForward()
      else if (event.text === "y") root.copyPath(root.selectedRow)
      else if (event.text === "r") root.beginRename(root.selectedRow)
      else if (event.text === "R") root.refresh(true)
      else if (event.text === "d") root.requestTrash(root.selectedRow)
      else if (event.text === "c") root.openDirectoryFinder()
      else if (event.text === ".") { root.showHidden = !root.showHidden; root.refresh(true) }
      else if (event.text === "s") { root.sidebarVisible = !root.sidebarVisible; root.saveState() }
      else if (event.text === "S") root.settingsOpen = !root.settingsOpen
      else if (event.text === "?") root.helpOpen = true
      else if (event.text === "q") root.dismissRequested()
      else return
      event.accepted = true
    }
  }

  Column {
    anchors.fill: parent

    Rectangle {
      id: toolbar
      width: parent.width
      height: Style.space(54)
      color: "transparent"

      Row {
        anchors.left: parent.left; anchors.leftMargin: Style.spacing.panelPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        ToolbarButton { glyph: "󰁍"; enabled: root.backHistory.length > 0; onClicked: root.goBack() }
        ToolbarButton { glyph: "󰁔"; enabled: root.forwardHistory.length > 0; onClicked: root.goForward() }
        ToolbarButton { glyph: "󰁞"; enabled: root.currentDirectory !== "/"; onClicked: root.goParent() }
      }

      Row {
        id: crumbs
        anchors.left: parent.left; anchors.leftMargin: Style.space(138)
        anchors.right: rightTools.left; anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(32)
        clip: true
        spacing: 0
        visible: !root.locationOpen

        Repeater {
          model: root.crumbRows()
          Row {
            required property var modelData
            required property int index
            spacing: Style.spacing.xs
            Text { visible: index > 0; text: "›"; color: Color.menu.text; opacity: .32; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Style.font.body }
            Rectangle {
              height: Style.space(28); width: crumbText.implicitWidth + Style.space(12); radius: Style.cornerRadius
              color: crumbMouse.containsMouse ? Style.hoverFillFor(Color.menu.text, Color.menu.selectedText) : "transparent"
              Text { id: crumbText; anchors.centerIn: parent; text: modelData.label; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.body; elide: Text.ElideMiddle }
              MouseArea { id: crumbMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.navigate(modelData.path, true) }
            }
          }
        }
      }

      TextField {
        id: locationField
        visible: root.locationOpen
        anchors.left: parent.left; anchors.leftMargin: Style.space(138)
        anchors.right: rightTools.left; anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: root.currentDirectory
        onAccepted: { root.locationOpen = false; root.navigate(text, true); keyCatcher.forceActiveFocus() }
        Keys.onEscapePressed: function(event) { root.locationOpen = false; keyCatcher.forceActiveFocus(); event.accepted = true }
      }

      Row {
        id: rightTools
        anchors.right: parent.right; anchors.rightMargin: Style.spacing.panelPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        TextField {
          id: searchField
          visible: root.searchOpen || root.filterText.length > 0
          width: Style.space(210)
          placeholderText: "Filter this folder"
          text: root.filterText
          onTextChanged: { root.filterText = text; rebuildTimer.restart() }
          onAccepted: {
            keyCatcher.forceActiveFocus()
            if (root.rows.length > 0) root.activateSelected()
          }
          Keys.onReturnPressed: function(event) {
            keyCatcher.forceActiveFocus()
            if (root.rows.length > 0) root.activateSelected()
            event.accepted = true
          }
          Keys.onEscapePressed: function(event) { root.searchOpen = false; root.filterText = ""; keyCatcher.forceActiveFocus(); event.accepted = true }
        }
        ToolbarButton {
          glyph: (root.searchOpen || root.filterText.length > 0) ? "󰅖" : "󰍉"
          onClicked: {
            if (root.searchOpen || root.filterText.length > 0) {
              root.searchOpen = false; root.filterText = ""; rebuildTimer.restart(); keyCatcher.forceActiveFocus()
            } else {
              root.searchOpen = true; Qt.callLater(function() { searchField.forceActiveFocus() })
            }
          }
        }
        ToolbarButton { glyph: "󰒺"; label: root.sortMode; onClicked: root.sortOpen = !root.sortOpen }
        Text { visible: root.width > Style.space(1100); anchors.verticalCenter: parent.verticalCenter; text: "󰋩"; color: Color.menu.text; opacity: .55; font.family: Style.font.family; font.pixelSize: Style.font.body }
        PanelSlider {
          visible: root.width > Style.space(1100)
          width: Style.space(135)
          anchors.verticalCenter: parent.verticalCenter
          minimum: Style.space(140)
          maximum: Style.space(420)
          step: Style.space(2)
          value: root.thumbnailWidth
          trackColor: Style.normalFillFor(Color.menu.text, Color.menu.selectedText)
          fillColor: Color.menu.selectedText
          knobColor: Color.menu.text
          onMoved: function(value) { root.thumbnailWidth = value }
          onReleased: function(value) { root.thumbnailWidth = value; root.saveState() }
        }
        Text { visible: root.width > Style.space(1100); anchors.verticalCenter: parent.verticalCenter; width: Style.space(34); text: Math.round(root.thumbnailWidth); color: Color.menu.text; opacity: .55; font.family: Style.font.family; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignRight }
        ToolbarButton { glyph: root.fullscreenActive ? "󰊓" : "󰊔"; onClicked: root.fullscreenToggleRequested() }
        ToolbarButton { glyph: "󰒓"; onClicked: { root.settingsOpen = !root.settingsOpen; root.sortOpen = false } }
        ToolbarButton { label: "?"; onClicked: root.helpOpen = true }
      }
    }

    Rectangle { width: parent.width; height: Math.max(1, Style.normalBorderWidth); color: Color.menu.border; opacity: .32 }

    Row {
      width: parent.width
      height: parent.height - toolbar.height - Style.normalBorderWidth

      Rectangle {
        visible: root.effectiveSidebarWidth > 0
        width: root.effectiveSidebarWidth
        height: parent.height
        color: Util.alpha(Color.menu.text, .025)

        Column {
          anchors.fill: parent; anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.xs

          Text { text: "PLACES"; color: Color.menu.text; opacity: .46; font.family: Style.font.family; font.pixelSize: Style.font.caption; leftPadding: Style.space(8); bottomPadding: Style.space(6) }
          Repeater {
            model: root.places
            Rectangle {
              required property var modelData
              width: parent.width; height: Style.space(34); radius: Style.cornerRadius
              color: root.currentDirectory === modelData.path ? Style.selectedFillFor(Color.menu.text, Color.menu.selectedText) : (placeMouse.containsMouse ? Style.hoverFillFor(Color.menu.text, Color.menu.selectedText) : "transparent")
              Text { anchors.left: parent.left; anchors.leftMargin: Style.space(9); anchors.verticalCenter: parent.verticalCenter; text: modelData.icon + "  " + modelData.name; color: root.currentDirectory === modelData.path ? Color.menu.selectedText : Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.body; elide: Text.ElideRight; width: parent.width - Style.space(18) }
              MouseArea { id: placeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.navigate(modelData.path, true) }
            }
          }
          Item { width: 1; height: Style.spacing.md }
          Text { text: "VIEW"; color: Color.menu.text; opacity: .46; font.family: Style.font.family; font.pixelSize: Style.font.caption; leftPadding: Style.space(8); bottomPadding: Style.space(6) }
          Rectangle {
            width: parent.width; height: Style.space(34); radius: Style.cornerRadius
            color: hiddenMouse.containsMouse ? Style.hoverFillFor(Color.menu.text, Color.menu.selectedText) : "transparent"
            Text { anchors.left: parent.left; anchors.leftMargin: Style.space(9); anchors.verticalCenter: parent.verticalCenter; text: (root.showHidden ? "󰈈" : "󰈉") + "  Hidden files"; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.body }
            MouseArea { id: hiddenMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { root.showHidden = !root.showHidden; root.refresh(true) } }
          }

          Item { width: 1; height: Math.max(1, parent.height - Style.space(250)) }
          Text { width: parent.width; text: root.loading ? "Reading folder…" : (root.rows.length + (root.rows.length === 1 ? " item" : " items")); color: Color.menu.text; opacity: .44; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
        }
      }

      Rectangle { visible: root.effectiveSidebarWidth > 0; width: visible ? Math.max(1, Style.normalBorderWidth) : 0; height: parent.height; color: Color.menu.border; opacity: .28 }

      Item {
        width: parent.width - root.effectiveSidebarWidth - (root.effectiveSidebarWidth > 0 ? Math.max(1, Style.normalBorderWidth) : 0)
        height: parent.height

        MasonryView {
          id: masonry
          anchors.fill: parent; anchors.margins: Style.spacing.md
          rows: root.rows
          selectedIndex: root.selectedIndex
          targetWidth: root.thumbnailWidth
          gap: root.gapSize
          showLabels: root.showLabels
          onSelectRequested: function(index) { root.select(index); keyCatcher.forceActiveFocus() }
          onActivateRequested: function(index) { root.select(index); root.activateSelected() }
          onContextRequested: function(index, sceneX, sceneY) { root.showContext(index, sceneX, sceneY) }
          onThumbnailRequested: function(path, kind) { root.requestThumbnail(path, kind) }
        }

        Column {
          anchors.centerIn: parent; spacing: Style.spacing.sm
          visible: root.enumerationDone && root.rows.length === 0
          Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.filterText ? "󰍉" : "󰉖"; color: Color.menu.text; opacity: .25; font.family: Style.font.family; font.pixelSize: Style.space(42) }
          Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.filterText ? "No files match “" + root.filterText + "”" : "This folder is empty"; color: Color.menu.text; opacity: .62; font.family: Style.font.family; font.pixelSize: Style.font.body }
        }

        Text {
          anchors.centerIn: parent; visible: root.statusMessage && !toastTimer.running
          text: root.statusMessage; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.body
        }
      }
    }
  }

  BorderSurface {
    visible: root.settingsOpen
    z: 25
    width: Math.min(root.width - Style.space(24), Style.space(410))
    height: settingsColumn.implicitHeight + Style.space(32)
    x: root.width - width - Style.spacing.panelPadding
    y: toolbar.height - Style.space(2)
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
    radius: Style.cornerRadius

    Column {
      id: settingsColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(16)
      spacing: Style.spacing.md

      Row {
        width: parent.width
        Text { width: parent.width - resetButton.width; text: "BROWSER SETTINGS"; color: Color.menu.text; opacity: .62; font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
        ToolbarButton { id: resetButton; label: "Reset"; onClicked: root.resetAppearance() }
      }

      SettingSlider {
        width: parent.width
        label: "Thumbnail width"
        minimum: Style.space(140); maximum: Style.space(420); step: Style.space(1)
        value: root.thumbnailWidth
        onMoved: function(value) { root.thumbnailWidth = value }
        onReleased: function(value) { root.thumbnailWidth = value; root.saveState() }
      }

      SettingSlider {
        width: parent.width
        label: "Grid gap"
        minimum: Style.space(2); maximum: Style.space(32); step: Style.space(1)
        value: root.gapSize
        onMoved: function(value) { root.gapSize = value }
        onReleased: function(value) { root.gapSize = value; root.saveState() }
      }

      SettingSlider {
        width: parent.width
        label: "Sidebar width"
        minimum: Style.space(150); maximum: Style.space(320); step: Style.space(2)
        value: root.sidebarWidth
        onMoved: function(value) { root.sidebarWidth = value }
        onReleased: function(value) { root.sidebarWidth = value; root.saveState() }
      }

      Toggle {
        width: parent.width
        label: "Show sidebar"
        description: "Toggle quickly with lowercase s in the browser"
        checked: root.sidebarVisible
        foreground: Color.menu.text
        accent: Color.menu.selectedText
        onClicked: { root.sidebarVisible = !root.sidebarVisible; root.saveState() }
      }

      Toggle {
        width: parent.width
        label: "Show filenames"
        description: "Hide labels for a denser, media-first layout"
        checked: root.showLabels
        foreground: Color.menu.text
        accent: Color.menu.selectedText
        onClicked: { root.showLabels = !root.showLabels; root.saveState() }
      }

      Toggle {
        width: parent.width
        label: "Folders first"
        description: "Keep folders ahead of files in every sort mode"
        checked: root.foldersFirst
        foreground: Color.menu.text
        accent: Color.menu.selectedText
        onClicked: { root.foldersFirst = !root.foldersFirst; root.rebuildRows(); root.saveState() }
      }

      Text {
        width: parent.width
        text: "F11 toggles fullscreen. As a normal Hyprland window, Quattro Files stays on its workspace."
        color: Color.menu.text
        opacity: .48
        wrapMode: Text.WordWrap
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  BorderSurface {
    visible: root.sortOpen
    z: 20
    width: Style.space(175); height: sortColumn.height + Style.space(16)
    x: root.width - width - Style.spacing.panelPadding; y: Style.space(48)
    color: Color.menu.background; borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth); radius: Style.cornerRadius
    Column {
      id: sortColumn
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(8)
      Repeater {
        model: [{key:"name",label:"Name"},{key:"modified",label:"Modified"},{key:"size",label:"Size"},{key:"type",label:"Type"}]
        Rectangle {
          required property var modelData
          width: parent.width; height: Style.space(31); radius: Style.cornerRadius
          color: root.sortMode === modelData.key ? Style.selectedFillFor(Color.menu.text, Color.menu.selectedText) : (sortMouse.containsMouse ? Style.hoverFillFor(Color.menu.text, Color.menu.selectedText) : "transparent")
          Text { anchors.left: parent.left; anchors.leftMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; text: (root.sortMode === modelData.key ? (root.sortDescending ? "󰒺  " : "󰒼  ") : "    ") + modelData.label; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          MouseArea { id: sortMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { if (root.sortMode === modelData.key) root.sortDescending = !root.sortDescending; else { root.sortMode = modelData.key; root.sortDescending = false }; root.sortOpen = false; root.rebuildRows(); root.saveState(); keyCatcher.forceActiveFocus() } }
        }
      }
    }
  }

  BorderSurface {
    visible: root.contextOpen
    z: 30; x: root.contextX; y: root.contextY; width: Style.space(185); height: contextColumn.height + Style.space(16)
    color: Color.menu.background; borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth); radius: Style.cornerRadius
    Column {
      id: contextColumn; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(8)
      Repeater {
        model: ["Open", "Open with default", "Copy path", "Rename", "Move to Trash"]
        Rectangle {
          required property string modelData
          width: parent.width; height: Style.space(31); radius: Style.cornerRadius
          color: contextMouse.containsMouse ? (modelData === "Move to Trash" ? Util.alpha(Color.urgent,.16) : Style.hoverFillFor(Color.menu.text, Color.menu.selectedText)) : "transparent"
          Text { anchors.left: parent.left; anchors.leftMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; text: modelData; color: modelData === "Move to Trash" ? Color.urgent : Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          MouseArea { id: contextMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { if (modelData === "Open") root.activateSelected(); else if (modelData === "Open with default") root.openDefault(root.actionRow); else if (modelData === "Copy path") root.copyPath(root.actionRow); else if (modelData === "Rename") root.beginRename(root.actionRow); else root.requestTrash(root.actionRow); root.contextOpen = false } }
        }
      }
    }
  }

  Rectangle {
    visible: root.renameOpen
    z: 50; anchors.fill: parent; color: Color.menu.scrim
    MouseArea { anchors.fill: parent; onClicked: { root.renameOpen = false; keyCatcher.forceActiveFocus() } }
    BorderSurface {
      width: Math.min(parent.width - Style.space(40), Style.space(440)); height: Style.space(125); anchors.centerIn: parent
      color: Color.menu.background; borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth); radius: Style.cornerRadius; padding: Style.space(18)
      MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }
      Column {
        anchors.fill: parent; anchors.margins: Style.space(18); spacing: Style.spacing.md
        Text { text: "Rename"; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.title }
        TextField { id: renameField; width: parent.width; onAccepted: root.commitRename(); Keys.onEscapePressed: function(event) { root.renameOpen = false; keyCatcher.forceActiveFocus(); event.accepted = true } }
      }
    }
  }

  ConfirmDialog {
    id: trashDialog
    z: 60; anchors.fill: parent; opened: root.trashOpen
    background: Color.menu.background; foreground: Color.menu.text; selectedText: Color.menu.selectedText
    confirmText: "Move to Trash"
    onCanceled: { root.trashOpen = false; keyCatcher.forceActiveFocus() }
    onConfirmed: root.confirmTrash()
  }

  BorderSurface {
    visible: toastTimer.running && root.statusMessage
    z: 90; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(24)
    width: toastText.implicitWidth + Style.space(24); height: Style.space(34); radius: Style.cornerRadius
    color: Color.menu.background; borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
    Text { id: toastText; anchors.centerIn: parent; text: root.statusMessage; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.caption }
  }

  QuickLook {
    id: quickLook
    anchors.fill: parent
    backend: root.backend
    rows: root.rows
    onCloseRequested: function(index) {
      root.select(index)
      keyCatcher.forceActiveFocus()
    }
  }

  DirectoryFinder {
    id: directoryFinder
    anchors.fill: parent
    backend: root.backend
    homePath: root.homePath
    onChosen: function(path) { root.navigate(path, true); keyCatcher.forceActiveFocus() }
    onCloseRequested: keyCatcher.forceActiveFocus()
  }

  KeyboardHelp {
    anchors.fill: parent
    visible: root.helpOpen
    z: 110
    onCloseRequested: { root.helpOpen = false; keyCatcher.forceActiveFocus() }
  }
}
