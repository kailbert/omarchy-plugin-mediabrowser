import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root
  property string glyph: ""
  property string label: ""
  property bool enabled: true
  signal clicked()

  implicitWidth: label ? text.implicitWidth + Style.space(20) : Style.space(32)
  implicitHeight: Style.space(30)
  radius: Style.cornerRadius
  color: pointer.containsMouse && enabled ? Style.hoverFillFor(Color.menu.text, Color.menu.selectedText) : "transparent"
  borderSpec: Border.controlSpec(pointer.containsMouse && enabled ? "hover-cursor" : "normal", Color.menu.text, Color.menu.selectedText)
  opacity: enabled ? 1 : .32

  Text {
    id: text
    anchors.centerIn: parent
    text: (root.glyph ? root.glyph + (root.label ? "  " : "") : "") + root.label
    color: Color.menu.text
    font.family: String(Style.font.family || "monospace")
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
