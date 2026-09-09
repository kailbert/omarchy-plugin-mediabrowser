import QtQuick
import qs.Commons

Item {
  id: root

  property var rows: []
  property int selectedIndex: 0
  property real targetWidth: Style.space(230)
  property real gap: Style.spacing.md
  property bool showLabels: true
  property int columns: 1
  property var layoutRows: []
  property real contentHeight: 0
  property bool layoutBusy: false
  property var markedPaths: ({})
  readonly property real scrollPosition: flick.contentY

  signal selectRequested(int index)
  signal activateRequested(int index)
  signal contextRequested(int index, real sceneX, real sceneY)
  signal thumbnailRequested(string path, string kind)

  function relayout() {
    var usable = Math.max(1, width)
    var count = Math.max(1, Math.floor((usable + gap) / (targetWidth + gap)))
    var cellWidth = Math.floor((usable - gap * (count - 1)) / count)
    var heights = []
    for (var c = 0; c < count; c++) heights.push(0)
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var column = 0
      for (var j = 1; j < count; j++) if (heights[j] < heights[column]) column = j
      var aspect = Math.max(0.15, Number(row.aspect || 1.333))
      var visualHeight
      if (row.kind === "folder" || row.kind === "file")
        visualHeight = Math.min(Style.space(128), cellWidth * .58)
      else visualHeight = Math.max(cellWidth * .25, Math.min(cellWidth * 2.65, cellWidth / aspect))
      var labelHeight = showLabels ? Style.space(31) : 0
      var tileHeight = Math.round(visualHeight + labelHeight)
      out.push({ index: i, x: column * (cellWidth + gap), y: heights[column], width: cellWidth,
                 height: tileHeight, mediaHeight: visualHeight, labelHeight: labelHeight, row: row, column: column })
      heights[column] += tileHeight + gap
    }
    columns = count
    layoutRows = out
    contentHeight = Math.max(0, Math.max.apply(Math, heights) - gap)
    rebuildVisible()
  }

  function rebuildVisible() {
    if (!layoutRows) return
    var top = Math.max(0, flick.contentY - flick.height)
    var bottom = flick.contentY + flick.height * 2
    var wanted = []
    var center = flick.contentY + flick.height / 2
    for (var i = 0; i < layoutRows.length; i++) {
      var item = layoutRows[i]
      if (item.y + item.height < top || item.y > bottom) continue
      var row = item.row
      wanted.push({
        displayIndex: item.index, tileX: item.x, tileY: item.y, tileWidth: item.width,
        tileHeight: item.height, mediaHeight: item.mediaHeight, labelHeight: item.labelHeight, filePath: String(row.path || ""),
        fileName: String(row.name || ""), kind: String(row.kind || "file"), mime: String(row.mime || ""),
        thumbnail: String(row.thumbnail || ""), duration: Number(row.duration || 0), broken: row.broken === true,
        distance: Math.abs(item.y + item.height / 2 - center)
      })
    }
    wanted.sort(function(a, b) { return a.distance - b.distance })

    // Reconcile in place so scrolling retains overlapping delegates and their
    // textures instead of destroying the entire visible viewport every frame.
    var keep = ({})
    for (var w = 0; w < wanted.length; w++) keep[String(wanted[w].displayIndex)] = true
    for (var old = visibleModel.count - 1; old >= 0; old--)
      if (!keep[String(visibleModel.get(old).displayIndex)]) visibleModel.remove(old)
    var existing = ({})
    for (var e = 0; e < visibleModel.count; e++) existing[String(visibleModel.get(e).displayIndex)] = e
    var fields = ["tileX","tileY","tileWidth","tileHeight","mediaHeight","labelHeight","filePath","fileName","kind","mime","thumbnail","duration","broken"]
    for (var n = 0; n < wanted.length; n++) {
      var value = wanted[n]
      var key = String(value.displayIndex)
      if (existing[key] === undefined) {
        visibleModel.append(value)
      } else {
        var modelIndex = existing[key]
        for (var f = 0; f < fields.length; f++) visibleModel.setProperty(modelIndex, fields[f], value[fields[f]])
      }
    }
  }

  function ensureVisible(index) {
    if (index < 0 || index >= layoutRows.length) return
    var item = layoutRows[index]
    if (item.y < flick.contentY) flick.contentY = item.y
    else if (item.y + item.height > flick.contentY + flick.height) flick.contentY = item.y + item.height - flick.height
  }

  function restoreView(index, scrollY) {
    if (index < 0 || index >= layoutRows.length) return
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), Number(scrollY || 0)))
    ensureVisible(index)
    rebuildVisible()
  }

  function centerSelected(index, alignment) {
    if (index < 0 || index >= layoutRows.length) return
    var item = layoutRows[index]
    var ratio = alignment === "top" ? 0 : (alignment === "bottom" ? 1 : .5)
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), item.y + item.height / 2 - flick.height * ratio))
  }

  function geometricNeighbor(index, dx, dy) {
    if (index < 0 || index >= layoutRows.length) return -1
    var current = layoutRows[index]
    var cx = current.x + current.width / 2
    var cy = current.y + current.height / 2
    var best = -1, bestScore = Number.MAX_VALUE
    for (var i = 0; i < layoutRows.length; i++) {
      if (i === index) continue
      var candidate = layoutRows[i]
      var tx = candidate.x + candidate.width / 2
      var ty = candidate.y + candidate.height / 2
      var rx = tx - cx, ry = ty - cy
      if ((dx < 0 && rx >= -1) || (dx > 0 && rx <= 1) || (dy < 0 && ry >= -1) || (dy > 0 && ry <= 1)) continue
      var primary = dx ? Math.abs(rx) : Math.abs(ry)
      var cross = dx ? Math.abs(ry) : Math.abs(rx)
      var score = primary + cross * 1.8
      if (score < bestScore) { bestScore = score; best = i }
    }
    return best
  }

  function page(delta) {
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + delta * flick.height * .85))
  }

  onRowsChanged: Qt.callLater(relayout)
  onWidthChanged: layoutTimer.restart()
  onTargetWidthChanged: layoutTimer.restart()
  onGapChanged: layoutTimer.restart()
  onShowLabelsChanged: layoutTimer.restart()

  Timer { id: layoutTimer; interval: 40; onTriggered: root.relayout() }
  Timer { id: visibleTimer; interval: 28; onTriggered: root.rebuildVisible() }
  ListModel { id: visibleModel }

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: Math.max(height, root.contentHeight)
    boundsBehavior: Flickable.StopAtBounds
    flickDeceleration: 2300
    onContentYChanged: visibleTimer.restart()

    Repeater {
      model: visibleModel

      MediaTile {
        required property var model

        displayIndex: model.displayIndex
        filePath: model.filePath
        fileName: model.fileName
        kind: model.kind
        mime: model.mime
        thumbnail: model.thumbnail
        duration: model.duration
        broken: model.broken
        marked: root.markedPaths[model.filePath] === true
        x: model.tileX
        y: model.tileY
        width: model.tileWidth
        height: model.tileHeight
        mediaHeight: model.mediaHeight
        labelHeight: model.labelHeight
        selected: model.displayIndex === root.selectedIndex
        onSelectedByMouse: function(index) { root.selectRequested(index) }
        onActivated: function(index) { root.activateRequested(index) }
        onContextRequested: function(index, sceneX, sceneY) { root.contextRequested(index, sceneX, sceneY) }
        onThumbnailNeeded: function(path, kind) { root.thumbnailRequested(path, kind) }
      }
    }
  }

  Rectangle {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(2)
    y: flick.visibleArea.yPosition * parent.height
    width: Style.space(3)
    height: Math.max(Style.space(24), flick.visibleArea.heightRatio * parent.height)
    radius: width / 2
    color: Color.menu.text
    opacity: flick.contentHeight > flick.height ? 0.28 : 0
  }
}
