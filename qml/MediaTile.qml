import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "BrowserModel.js" as BrowserModel

BorderSurface {
  id: root

  required property int displayIndex
  required property string filePath
  required property string fileName
  required property string kind
  required property string mime
  required property string thumbnail
  required property real duration
  required property bool broken
  property bool selected: false
  property real mediaHeight: Math.max(1, height - labelHeight)
  property real labelHeight: Style.space(31)

  signal selectedByMouse(int index)
  signal activated(int index)
  signal contextRequested(int index, real sceneX, real sceneY)
  signal thumbnailNeeded(string path, string kind)

  color: selected ? Style.selectedFillFor(Color.menu.text, Color.menu.selectedText) : Style.normalFillFor(Color.menu.text, Color.menu.selectedText)
  borderSpec: Border.none()
  radius: Style.cornerRadius
  clip: true

  Component.onCompleted: if ((kind === "image" || kind === "video") && !thumbnail) thumbnailNeeded(filePath, kind)

  Rectangle {
    id: tileMask
    anchors.fill: parent
    visible: false
    radius: root.radius
    color: "white"
    layer.enabled: true
  }

  Item {
    id: clippedContent
    anchors.fill: parent
    layer.enabled: root.radius > 0
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: tileMask
      maskThresholdMin: 0.3
      maskSpreadAtMin: 0.3
    }

  Rectangle {
    id: visual
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.mediaHeight
    color: Util.alpha(Color.menu.text, 0.035)
    clip: true

    Image {
      id: preview
      anchors.fill: parent
      source: root.thumbnail ? Util.fileUrl(root.thumbnail) : ""
      asynchronous: true
      cache: true
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.max(64, width * Screen.devicePixelRatio)
      sourceSize.height: Math.max(64, height * Screen.devicePixelRatio)
      visible: root.thumbnail && status !== Image.Error
    }

    Column {
      anchors.centerIn: parent
      spacing: Style.spacing.xs
      visible: !preview.visible

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.kind === "folder" ? "󰉋" : (root.kind === "video" ? "󰕧" : (root.kind === "image" ? "󰋩" : "󰈔"))
        color: root.broken ? Color.urgent : Color.menu.text
        opacity: root.kind === "folder" ? 0.82 : 0.42
        font.family: String(Style.font.family || "monospace")
        font.pixelSize: root.kind === "folder" ? Style.space(34) : Style.space(26)
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.broken
        text: "unreadable"
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Rectangle {
      visible: root.kind === "video"
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(6)
      height: Style.space(20)
      width: durationText.implicitWidth + Style.space(12)
      radius: Style.cornerRadius
      color: Qt.rgba(0, 0, 0, 0.72)

      Text {
        id: durationText
        anchors.centerIn: parent
        text: root.duration > 0 ? "󰐊  " + BrowserModel.formatDuration(root.duration) : "󰕧"
        color: "white"
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  Text {
    visible: root.labelHeight > 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    height: root.labelHeight
    text: root.fileName
    color: root.selected ? Color.menu.selectedText : Color.menu.text
    opacity: root.selected ? 1 : 0.82
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideMiddle
  }
  }

  BorderSurface {
    anchors.fill: parent
    z: 2
    color: "transparent"
    radius: root.radius
    borderSpec: root.selected
      ? Border.withWidth(Border.controlSpec("selected", Color.menu.text, Color.accent), Math.max(Style.space(2), Style.selectedBorderWidth))
      : Border.controlSpec(pointer.containsMouse ? "hover-cursor" : "normal", Color.menu.text, Color.accent)
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: root.kind === "folder" ? Qt.PointingHandCursor : Qt.ArrowCursor
    onPressed: function(mouse) { root.selectedByMouse(root.displayIndex) }
    onDoubleClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.activated(root.displayIndex) }
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        var point = root.mapToItem(null, mouse.x, mouse.y)
        root.contextRequested(root.displayIndex, point.x, point.y)
      }
    }
  }
}
