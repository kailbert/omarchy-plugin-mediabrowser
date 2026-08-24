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
      if (row.kind === "folder") visualHeight = Math.min(Style.space(128), cellWidth * .58)
      else if (row.kind === "file") visualHeight = Math.min(Style.space(105), cellWidth * .48)
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
    visibleModel.clear()
    for (var i = 0; i < layoutRows.length; i++) {
      var item = layoutRows[i]
      if (item.y + item.height < top || item.y > bottom) continue
      var row = item.row
      visibleModel.append({
        displayIndex: item.index, tileX: item.x, tileY: item.y, tileWidth: item.width,
        tileHeight: item.height, mediaHeight: item.mediaHeight, labelHeight: item.labelHeight, filePath: String(row.path || ""),
        fileName: String(row.name || ""), kind: String(row.kind || "file"), mime: String(row.mime || ""),
        thumbnail: String(row.thumbnail || ""), duration: Number(row.duration || 0), broken: row.broken === true
      })
    }
  }

  function ensureVisible(index) {
    if (index < 0 || index >= layoutRows.length) return
    var item = layoutRows[index]
    if (item.y < flick.contentY) flick.contentY = item.y
    else if (item.y + item.height > flick.contentY + flick.height) flick.contentY = item.y + item.height - flick.height
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
