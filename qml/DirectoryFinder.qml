import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var backend: null
  property bool opened: false
  property bool scanning: false
  property bool limited: false
  property string requestId: ""
  property string scanRoot: ""
  property string homePath: ""
  property string query: ""
  property var rows: []
  property var pendingRows: []
  property var matches: []
  property int selectedIndex: 0
  property var seeds: []

  signal chosen(string path)
  signal closeRequested()

  function show(rootPath, seedRows) {
    if (!backend) return
    scanRoot = String(rootPath || "")
    requestId = backend.nextRequestId("directories")
    query = ""
    rows = []
    pendingRows = []
    matches = []
    selectedIndex = 0
    scanning = true
    limited = false
    opened = true
    seeds = seedRows || []
    backend.send({command: "find-directories", requestId: requestId, root: scanRoot,
                  hidden: false, depth: 5, limit: 1200, seeds: seeds})
    Qt.callLater(function() { finderField.forceActiveFocus() })
  }

  function close() {
    opened = false
    scanning = false
    closeRequested()
  }

  function choose() {
    if (!matches.length || selectedIndex < 0 || selectedIndex >= matches.length) return
    var path = matches[selectedIndex].path
    opened = false
    chosen(path)
  }

  function displayPath(row) {
    var prefix = scanRoot === homePath ? "~" : scanRoot.replace(/\/$/, "")
    return prefix + "/" + row.relative
  }

  function fuzzyScore(value, needle) {
    var text = String(value || "").toLocaleLowerCase()
    var find = String(needle || "").trim().toLocaleLowerCase()
    if (!find) return 0
    var at = 0, score = 0, previous = -2
    for (var i = 0; i < find.length; i++) {
      var found = text.indexOf(find.charAt(i), at)
      if (found < 0) return -1000000
      score += found === previous + 1 ? 12 : 2
      if (found === 0 || "/-_ ".indexOf(text.charAt(found - 1)) >= 0) score += 9
      score -= found - at
      previous = found
      at = found + 1
    }
    return score - text.length * .015
  }

  function rebuild() {
    var needle = query
    var scored = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var score = fuzzyScore(row.relative, needle)
      if (row.source === "bookmark") score += 500
      else if (row.source === "recent") score += 300
      else if (row.source === "zoxide") score += 180
      if (score > -1000000) scored.push({path: row.path, name: row.name, relative: row.relative, source: row.source || "scan", score: score})
    }
    scored.sort(function(a, b) {
      if (a.score !== b.score) return b.score - a.score
      return a.relative.localeCompare(b.relative)
    })
    matches = scored.slice(0, 200)
    selectedIndex = matches.length ? Math.max(0, Math.min(selectedIndex, matches.length - 1)) : 0
  }

  function flushPending() {
    if (!pendingRows.length) return
    rows = rows.concat(pendingRows)
    pendingRows = []
    rebuildTimer.restart()
  }

  Connections {
    target: root.backend
    function onHelperMessage(message) {
      if (message.requestId !== root.requestId) return
      if (message.event === "directory-entry") {
        root.pendingRows.push(message)
        batchTimer.restart()
      } else if (message.event === "directories-end") {
        root.flushPending()
        root.scanning = false
        root.limited = message.limited === true
      } else if (message.event === "directories-error") {
        root.scanning = false
      }
    }
  }

  Timer { id: batchTimer; interval: 55; onTriggered: root.flushPending() }
  Timer { id: rebuildTimer; interval: 30; onTriggered: root.rebuild() }

  visible: opened
  z: 95

  Rectangle { anchors.fill: parent; color: Color.menu.scrim }
  MouseArea { anchors.fill: parent; onClicked: root.close() }

  BorderSurface {
    width: Math.min(parent.width - Style.space(32), Style.space(660))
    height: Math.min(parent.height - Style.space(40), Style.space(570))
    anchors.centerIn: parent
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
    radius: Style.cornerRadius

    MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(16)
      spacing: Style.spacing.md

      Row {
        width: parent.width
        spacing: Style.spacing.md
        TextField {
          id: finderField
          width: parent.width - statusText.width - parent.spacing
          placeholderText: "Jump to a directory…"
          text: root.query
          onTextChanged: { root.query = text; root.selectedIndex = 0; rebuildTimer.restart() }
          onAccepted: root.choose()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
            else if (event.key === Qt.Key_Down || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_N)) {
              root.selectedIndex = Math.min(root.matches.length - 1, root.selectedIndex + 1); resultView.positionViewAtIndex(root.selectedIndex, ListView.Contain); event.accepted = true
            } else if (event.key === Qt.Key_Up || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_P)) {
              root.selectedIndex = Math.max(0, root.selectedIndex - 1); resultView.positionViewAtIndex(root.selectedIndex, ListView.Contain); event.accepted = true
            }
          }
        }
        Text {
          id: statusText
          width: Style.space(100)
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: root.scanning ? "scanning…" : root.matches.length + (root.limited ? "+ dirs" : " dirs")
          color: Color.menu.text; opacity: .5
          font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
      }

      Rectangle { width: parent.width; height: Math.max(1, Style.normalBorderWidth); color: Color.menu.border; opacity: .35 }

      ListView {
        id: resultView
        width: parent.width
        height: parent.height - finderField.height - Style.space(30)
        clip: true
        model: root.matches
        spacing: Style.spacing.xs

        delegate: Rectangle {
          required property var modelData
          required property int index
          width: resultView.width
          height: Style.space(46)
          radius: Style.cornerRadius
          color: index === root.selectedIndex ? Style.selectedFillFor(Color.menu.text, Color.menu.selectedText)
                                                : (rowMouse.containsMouse ? Style.hoverFillFor(Color.menu.text, Color.menu.selectedText) : "transparent")

          Text {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: (modelData.source === "bookmark" ? "󰃀" : (modelData.source === "recent" ? "󰋚" : "󰉋")) + "  "
                  + (modelData.source === "scan" ? root.displayPath(modelData) : modelData.path.replace(root.homePath, "~"))
            color: index === root.selectedIndex ? Color.menu.selectedText : Color.menu.text
            font.family: Style.font.family; font.pixelSize: Style.font.body
            elide: Text.ElideMiddle
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.selectedIndex = index
            onDoubleClicked: { root.selectedIndex = index; root.choose() }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: !root.scanning && root.matches.length === 0
          text: "No matching directories"
          color: Color.menu.text; opacity: .55
          font.family: Style.font.family; font.pixelSize: Style.font.body
        }
      }
    }
  }
}
