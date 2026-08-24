import Quickshell
import QtQuick
import QtMultimedia
import qs.Commons
import qs.Ui
import "BrowserModel.js" as BrowserModel

Item {
  id: root

  property var backend: null
  property var rows: []
  property int currentIndex: -1
  property bool opened: false
  property string previewSource: ""
  property string previewRequestId: ""
  property string zoomSource: ""
  property real zoomFactor: 0
  property bool controlsVisible: true
  property bool infoVisible: false
  property bool pendingCenter: false
  property var pendingZoomAnchor: null
  readonly property var current: currentIndex >= 0 && currentIndex < rows.length ? rows[currentIndex] : null
  readonly property bool isVideo: current && current.kind === "video"
  readonly property bool isGif: current && String(current.name || "").toLowerCase().endsWith(".gif")
  readonly property bool zoomed: !isVideo && !isGif && zoomFactor > 0

  signal closeRequested(int index)

  function show(index) {
    if (index < 0 || index >= rows.length) return
    currentIndex = index
    controlsVisible = true
    infoVisible = false
    opened = true
    loadCurrent()
  }

  function close() {
    var wasOpened = opened
    var closingIndex = currentIndex
    player.stop()
    player.source = ""
    animated.playing = false
    previewSource = ""
    zoomSource = ""
    zoomFactor = 0
    controlsVisible = true
    pendingCenter = false
    pendingZoomAnchor = null
    opened = false
    if (wasOpened && closingIndex >= 0) closeRequested(closingIndex)
  }

  function loadCurrent() {
    player.stop()
    player.source = ""
    previewSource = current && current.thumbnail ? Util.fileUrl(current.thumbnail) : ""
    zoomSource = ""
    zoomFactor = 0
    pendingCenter = false
    pendingZoomAnchor = null
    errorLabel.text = ""
    if (!current) return
    if (isVideo) {
      player.source = Util.fileUrl(current.path)
      player.play()
    } else if (!isGif && backend) {
      previewRequestId = backend.nextRequestId("preview")
      backend.send({command: "thumbnail", requestId: previewRequestId, path: current.path, kind: "image", width: 2200})
    }
    if (isGif) animated.playing = true
  }

  function move(delta) {
    if (!rows.length) return
    var index = currentIndex
    for (var tries = 0; tries < rows.length; tries++) {
      index = (index + delta + rows.length) % rows.length
      if (rows[index].kind === "image" || rows[index].kind === "video") {
        currentIndex = index
        loadCurrent()
        return
      }
    }
  }

  function togglePlayback() {
    if (!isVideo) { close(); return }
    if (player.playbackState === MediaPlayer.PlayingState) player.pause()
    else player.play()
  }

  function toggleMute() { audio.muted = !audio.muted }

  function toggleControls() { controlsVisible = !controlsVisible }
  function toggleInfo() { infoVisible = !infoVisible }
  function openExternal() { if (current) Quickshell.execDetached(["xdg-open", current.path]) }
  function copyCurrentPath() { if (current) Quickshell.execDetached(["wl-copy", current.path]) }
  function adjustVolume(delta) { audio.volume = Math.max(0, Math.min(1, audio.volume + delta)) }

  function fitImage() {
    zoomFactor = 0
    zoomSource = ""
    pendingCenter = false
    pendingZoomAnchor = null
  }

  function fittedScale() {
    if (current && current.width && current.height)
      return Math.min(1, imageViewport.width / current.width, imageViewport.height / current.height)
    if (fittedImage.implicitWidth > 0)
      return Math.min(1, fittedImage.paintedWidth / fittedImage.implicitWidth)
    return 1
  }

  function actualSize() {
    zoomSource = current ? Util.fileUrl(current.path) : ""
    zoomFactor = 1
    pendingCenter = true
    pendingZoomAnchor = null
    Qt.callLater(centerWhenReady)
  }

  function adjustZoom(multiplier) {
    zoomAt(multiplier, imageViewport.width / 2, imageViewport.height / 2)
  }

  function zoomAt(multiplier, viewportX, viewportY) {
    zoomSource = current ? Util.fileUrl(current.path) : ""
    var base = zoomed ? zoomFactor : fittedScale()
    var oldWidth = zoomed ? Math.max(1, zoomImage.width) : Math.max(1, fittedImage.paintedWidth)
    var oldHeight = zoomed ? Math.max(1, zoomImage.height) : Math.max(1, fittedImage.paintedHeight)
    var oldX = zoomed ? zoomImage.x : (imageViewport.width - oldWidth) / 2
    var oldY = zoomed ? zoomImage.y : (imageViewport.height - oldHeight) / 2
    var pointerX = zoomed ? imageFlick.contentX + viewportX : viewportX
    var pointerY = zoomed ? imageFlick.contentY + viewportY : viewportY
    var rx = Math.max(0, Math.min(1, (pointerX - oldX) / oldWidth))
    var ry = Math.max(0, Math.min(1, (pointerY - oldY) / oldHeight))
    zoomFactor = Math.max(.05, Math.min(8, base * multiplier))
    pendingCenter = false
    pendingZoomAnchor = {rx: rx, ry: ry, x: viewportX, y: viewportY}
    Qt.callLater(applyPendingZoomAnchor)
  }

  function clampScroll(value, contentSize, viewportSize) {
    return Math.max(0, Math.min(Math.max(0, contentSize - viewportSize), value))
  }

  function centerWhenReady() {
    if (!pendingCenter || zoomImage.status !== Image.Ready) return
    imageFlick.contentX = Math.max(0, (imageFlick.contentWidth - imageFlick.width) / 2)
    imageFlick.contentY = Math.max(0, (imageFlick.contentHeight - imageFlick.height) / 2)
    pendingCenter = false
  }

  function applyPendingZoomAnchor() {
    if (!pendingZoomAnchor || zoomImage.status !== Image.Ready) return
    var anchor = pendingZoomAnchor
    imageFlick.contentX = clampScroll(zoomImage.x + anchor.rx * zoomImage.width - anchor.x, imageFlick.contentWidth, imageFlick.width)
    imageFlick.contentY = clampScroll(zoomImage.y + anchor.ry * zoomImage.height - anchor.y, imageFlick.contentHeight, imageFlick.height)
    pendingZoomAnchor = null
  }

  function seekRelative(ms) {
    if (isVideo && player.seekable) player.position = Math.max(0, Math.min(player.duration, player.position + ms))
  }

  Connections {
    target: root.backend
    function onHelperMessage(message) {
      if (message.event === "thumbnail" && message.requestId === root.previewRequestId && root.current && message.path === root.current.path)
        root.previewSource = Util.fileUrl(message.thumbnail)
      else if (message.event === "thumbnail-error" && message.requestId === root.previewRequestId)
        errorLabel.text = "Unable to preview this image"
    }
  }

  visible: opened
  z: 100

  Rectangle { anchors.fill: parent; color: "black" }

  Item {
    id: imageViewport
    anchors.fill: parent

    Image {
      id: fittedImage
      anchors.centerIn: parent
      width: Math.min(parent.width, implicitWidth > 0 ? implicitWidth : parent.width)
      height: Math.min(parent.height, implicitHeight > 0 ? implicitHeight : parent.height)
      visible: root.current && !root.isVideo && !root.isGif && !root.zoomed
      source: root.previewSource
      asynchronous: true
      cache: true
      fillMode: Image.PreserveAspectFit
    }

    Flickable {
      id: imageFlick
      anchors.fill: parent
      visible: root.current && !root.isVideo && !root.isGif && root.zoomed
      clip: true
      interactive: false
      boundsBehavior: Flickable.StopAtBounds
      contentWidth: Math.max(width, zoomImage.width)
      contentHeight: Math.max(height, zoomImage.height)

      Image {
        id: zoomImage
        x: Math.max(0, (imageFlick.width - width) / 2)
        y: Math.max(0, (imageFlick.height - height) / 2)
        source: root.zoomSource
        asynchronous: true
        cache: false
        width: Math.max(1, implicitWidth * root.zoomFactor)
        height: Math.max(1, implicitHeight * root.zoomFactor)
        fillMode: Image.Stretch
        onStatusChanged: {
          if (status === Image.Error && root.previewSource) root.zoomSource = root.previewSource
          else if (status === Image.Ready) {
            Qt.callLater(root.centerWhenReady)
            Qt.callLater(root.applyPendingZoomAnchor)
          }
        }
      }

      DragHandler {
        id: panDrag
        target: null
        enabled: root.zoomed
        property real startX: 0
        property real startY: 0
        onActiveChanged: if (active) {
          startX = imageFlick.contentX
          startY = imageFlick.contentY
        }
        onTranslationChanged: if (active) {
          imageFlick.contentX = root.clampScroll(startX - translation.x, imageFlick.contentWidth, imageFlick.width)
          imageFlick.contentY = root.clampScroll(startY - translation.y, imageFlick.contentHeight, imageFlick.height)
        }
      }

      HoverHandler { cursorShape: panDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
    }

    // A MouseArea with no accepted buttons receives wheel and touchpad-scroll
    // events without competing with the Flickable/DragHandler for a pointer
    // grab. WheelHandler arbitration allowed some Wayland devices to scroll
    // the underlying viewport instead of reaching our zoom callback.
    MouseArea {
      anchors.fill: parent
      enabled: root.current && !root.isVideo && !root.isGif
      acceptedButtons: Qt.NoButton
      scrollGestureEnabled: true
      preventStealing: true
      onWheel: function(event) {
        var delta = event.angleDelta.y
        var multiplier
        if (delta !== 0) multiplier = Math.pow(1.16, delta / 120)
        else {
          delta = event.pixelDelta.y
          if (delta === 0) return
          multiplier = Math.pow(1.0025, delta)
        }
        event.accepted = true
        root.zoomAt(multiplier, event.x, event.y)
      }
    }

    TapHandler {
      acceptedButtons: Qt.LeftButton
      onTapped: if (!root.controlsVisible) root.controlsVisible = true
      onDoubleTapped: {
        if (root.current && !root.isVideo && !root.isGif) {
          if (root.zoomed) root.fitImage()
          else root.actualSize()
        }
      }
    }
  }

  AnimatedImage {
    id: animated
    anchors.centerIn: parent
    width: Math.min(parent.width, implicitWidth > 0 ? implicitWidth : parent.width)
    height: Math.min(parent.height, implicitHeight > 0 ? implicitHeight : parent.height)
    visible: root.current && root.isGif
    source: visible ? Util.fileUrl(root.current.path) : ""
    asynchronous: true
    cache: false
    fillMode: Image.PreserveAspectFit
    playing: false
  }

  VideoOutput {
    id: videoOutput
    anchors.fill: parent
    visible: root.isVideo
    fillMode: VideoOutput.PreserveAspectFit
  }

  MediaPlayer {
    id: player
    videoOutput: videoOutput
    audioOutput: AudioOutput { id: audio; volume: .8 }
    onErrorOccurred: function(error, errorString) { errorLabel.text = errorString || "Unable to play this video" }
  }

  Text {
    id: errorLabel
    anchors.centerIn: parent
    width: parent.width * .7
    visible: text
    color: Color.urgent
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    maximumLineCount: 3
    elide: Text.ElideRight
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  BorderSurface {
    visible: root.infoVisible && root.current
    z: 4
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: Style.space(18)
    width: Math.min(parent.width - Style.space(36), Style.space(390))
    height: infoColumn.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: Qt.rgba(0, 0, 0, .76)
    borderSpec: Border.withWidth(Border.controlSpec("normal", "white", Color.accent), 1)
    Column {
      id: infoColumn
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
      anchors.margins: Style.space(12)
      spacing: Style.spacing.xs
      Text { width: parent.width; text: root.current ? root.current.name : ""; color: "white"; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideMiddle }
      Text { text: root.current ? String(root.current.mime || root.current.kind) : ""; color: "white"; opacity: .58; font.family: Style.font.family; font.pixelSize: Style.font.caption }
      Text { text: root.current && root.current.width ? root.current.width + " × " + root.current.height : ""; visible: text.length > 0; color: "white"; opacity: .72; font.family: Style.font.family; font.pixelSize: Style.font.caption }
      Text { text: root.current ? BrowserModel.formatBytes(root.current.size || 0) : ""; color: "white"; opacity: .72; font.family: Style.font.family; font.pixelSize: Style.font.caption }
      Text { text: root.current && root.current.mtime ? new Date(root.current.mtime * 1000).toLocaleString() : ""; visible: text.length > 0; color: "white"; opacity: .72; font.family: Style.font.family; font.pixelSize: Style.font.caption }
      Text { width: parent.width; text: root.current ? root.current.path : ""; color: "white"; opacity: .48; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle }
    }
  }

  Item {
    id: chrome
    anchors.fill: parent
    visible: root.controlsVisible

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(104)
      gradient: Gradient {
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, .88) }
      }
    }

    Row {
      id: bottomControls
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(22)
      anchors.rightMargin: Style.space(22)
      anchors.bottomMargin: Style.space(15)
      height: Style.space(38)
      spacing: Style.spacing.md

      Text {
        width: Math.min(implicitWidth, parent.width * (root.isVideo ? .22 : .32))
        anchors.verticalCenter: parent.verticalCenter
        text: root.current ? root.current.name : ""
        color: "white"
        opacity: .86
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }

      Row {
        visible: root.current && !root.isVideo && !root.isGif
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(5)

        Repeater {
          model: ["Fit", "100%", "−", "+"]
          Rectangle {
            required property string modelData
            width: modelData.length > 1 ? Style.space(48) : Style.space(30)
            height: Style.space(28)
            radius: Style.cornerRadius
            color: zoomMouse.containsMouse ? Qt.rgba(1,1,1,.16) : "transparent"
            border.color: Qt.rgba(1,1,1,.22)
            border.width: 1
            Text { anchors.centerIn: parent; text: modelData; color: "white"; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            MouseArea {
              id: zoomMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                if (modelData === "Fit") root.fitImage()
                else if (modelData === "100%") root.actualSize()
                else if (modelData === "−") root.adjustZoom(.8)
                else root.adjustZoom(1.25)
              }
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.zoomed ? Math.round(root.zoomFactor * 100) + "%" : "fit"
          color: "white"
          opacity: .55
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        visible: root.isVideo
        width: Style.space(32)
        height: Style.space(28)
        anchors.verticalCenter: parent.verticalCenter
        radius: Style.cornerRadius
        color: playMouse.containsMouse ? Qt.rgba(1,1,1,.16) : "transparent"
        Text { anchors.centerIn: parent; text: player.playbackState === MediaPlayer.PlayingState ? "󰏤" : "󰐊"; color: "white"; font.family: String(Style.font.family || "monospace"); font.pixelSize: Style.font.title }
        MouseArea { id: playMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.togglePlayback() }
      }

      Rectangle {
        id: track
        visible: root.isVideo
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(4)
        width: Math.max(Style.space(80), root.width - Style.space(520))
        radius: height / 2
        color: Qt.rgba(1,1,1,.2)
        Rectangle { width: player.duration > 0 ? parent.width * player.position / player.duration : 0; height: parent.height; radius: height / 2; color: Color.accent }
        MouseArea { anchors.fill: parent; onPressed: function(mouse) { if (player.duration > 0) player.position = player.duration * mouse.x / width } }
      }

      Text {
        visible: root.isVideo
        anchors.verticalCenter: parent.verticalCenter
        text: BrowserModel.formatDuration(player.position / 1000) + " / " + BrowserModel.formatDuration(player.duration / 1000)
        color: "white"
        opacity: .72
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        visible: root.isVideo
        width: Style.space(32); height: Style.space(28); anchors.verticalCenter: parent.verticalCenter
        color: muteMouse.containsMouse ? Qt.rgba(1,1,1,.16) : "transparent"; radius: Style.cornerRadius
        Text { anchors.centerIn: parent; text: audio.muted ? "󰝟" : "󰕾"; color: "white"; font.family: String(Style.font.family || "monospace"); font.pixelSize: Style.font.title }
        MouseArea { id: muteMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleMute() }
      }

      Text {
        visible: root.isVideo
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(audio.volume * 100) + "%"
        color: "white"; opacity: .52
        font.family: Style.font.family; font.pixelSize: Style.font.caption
      }

      Item { width: 1; height: 1 }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.current && root.current.width ? root.current.width + " × " + root.current.height : ""
        color: "white"; opacity: .52
        font.family: Style.font.family; font.pixelSize: Style.font.caption
      }

      Rectangle {
        width: Style.space(68)
        height: Style.space(28)
        anchors.verticalCenter: parent.verticalCenter
        radius: Style.cornerRadius
        color: hideMouse.containsMouse ? Qt.rgba(1,1,1,.16) : "transparent"
        border.color: Qt.rgba(1,1,1,.22)
        border.width: 1
        Text { anchors.centerIn: parent; text: "Hide  C"; color: "white"; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        MouseArea { id: hideMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.controlsVisible = false }
      }
    }

    Text {
      anchors.top: parent.top; anchors.right: parent.right; anchors.margins: Style.space(18)
      text: root.isVideo ? "Q / ESC  close   H L  browse   ← →  seek   J K  volume"
                         : "Q / ESC  close   H L  browse   1  100%   wheel  zoom"
      color: "white"; opacity: .58
      font.family: Style.font.family; font.pixelSize: Style.font.caption
    }

    Repeater {
      model: [{side: "left", glyph: "‹", delta: -1}, {side: "right", glyph: "›", delta: 1}]
      Rectangle {
        required property var modelData
        width: Style.space(38); height: Style.space(62)
        anchors.verticalCenter: parent.verticalCenter
        x: modelData.side === "left" ? Style.space(14) : parent.width - width - Style.space(14)
        radius: Style.cornerRadius
        color: navMouse.containsMouse ? Qt.rgba(0,0,0,.72) : Qt.rgba(0,0,0,.38)
        border.color: Qt.rgba(1,1,1,.18)
        Text { anchors.centerIn: parent; text: modelData.glyph; color: "white"; font.family: Style.font.family; font.pixelSize: Style.space(28) }
        MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.move(modelData.delta) }
      }
    }
  }
}
