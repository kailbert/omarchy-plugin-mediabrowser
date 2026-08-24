import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string label: ""
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 1
  property string suffix: " px"

  signal moved(real value)
  signal released(real value)

  implicitHeight: Style.space(50)
  implicitWidth: Style.space(360)

  Text {
    anchors.left: parent.left
    anchors.top: parent.top
    text: root.label
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Text {
    anchors.right: parent.right
    anchors.top: parent.top
    text: Math.round(root.value) + root.suffix
    color: Color.menu.text
    opacity: .55
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  PanelSlider {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    minimum: root.minimum
    maximum: root.maximum
    step: root.step
    value: root.value
    trackColor: Style.normalFillFor(Color.menu.text, Color.menu.selectedText)
    fillColor: Color.menu.selectedText
    knobColor: Color.menu.text
    onMoved: function(value) { root.moved(value) }
    onReleased: function(value) { root.released(value) }
  }
}
