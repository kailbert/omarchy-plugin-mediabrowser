import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool closingFromHost: false
  property bool backendReady: false
  property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  property string helperPath: pluginDir + "/helper/quattro-files-helper"
  property string watchPath: ""
  property int requestCounter: 0

  signal helperMessage(var message)

  function nextRequestId(prefix) {
    requestCounter++
    return prefix + "-" + requestCounter
  }

  function send(message) {
    if (!backend.running || !backendReady) return false
    backend.write(JSON.stringify(message) + "\n")
    return true
  }

  function handleLine(line) {
    try {
      var message = JSON.parse(line)
      if (message.event === "ready") backendReady = true
      helperMessage(message)
    } catch (e) {
      console.warn("Quattro Files: invalid helper output", e)
    }
  }

  function open(payloadJson) {
    closingFromHost = false
    opened = true
    window.visible = true
    if (!backend.running) backend.running = true
    var payload = ({})
    try { if (payloadJson) payload = JSON.parse(payloadJson) } catch (e) { }
    browser.openPath = String(payload.path || payload.directory || "")
    Qt.callLater(function() { browser.activate() })
  }

  function close() {
    closingFromHost = true
    opened = false
    browser.deactivate()
    watchProc.running = false
    window.visible = false
    closingFromHost = false
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "quattro.files")
  }

  function setWatch(path) {
    watchPath = String(path || "")
    watchProc.running = false
    watchStart.restart()
  }

  Component.onDestruction: {
    if (backend.running && backendReady) backend.write('{"command":"quit"}\n')
  }

  Process {
    id: backend
    command: [root.helperPath, "serve"]
    stdinEnabled: true
    onStarted: root.backendReady = false
    onExited: function(exitCode, exitStatus) {
      root.backendReady = false
      root.helperMessage({event: "error", operation: "backend", message: "File helper stopped; reconnecting…"})
      if (root.opened) backendRestart.restart()
    }
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    stderr: SplitParser { onRead: function(line) { console.warn("Quattro Files helper:", line) } }
  }

  Timer {
    id: backendRestart
    interval: 1500
    onTriggered: if (root.opened && !backend.running) backend.running = true
  }

  Process {
    id: watchProc
    command: ["inotifywait", "-m", "-q", "-e", "create,delete,moved_to,moved_from,close_write,attrib", "--format", "%e", "--", root.watchPath]
    stdout: SplitParser { onRead: function(line) { if (root.opened) browser.externalChange() } }
  }

  Timer {
    id: watchStart
    interval: 120
    onTriggered: if (root.opened && root.watchPath) watchProc.running = true
  }

  FloatingWindow {
    id: window
    visible: false
    title: "Quattro Files"
    color: "transparent"
    implicitWidth: 1500
    implicitHeight: 940
    minimumSize: Qt.size(820, 520)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.opened) root.dismiss()
    }

    Browser {
      id: browser
      anchors.fill: parent
      backend: root
      fullscreenActive: window.fullscreen
      onDismissRequested: root.dismiss()
      onWatchRequested: function(path) { root.setWatch(path) }
      onFullscreenToggleRequested: window.fullscreen = !window.fullscreen
    }
  }
}
