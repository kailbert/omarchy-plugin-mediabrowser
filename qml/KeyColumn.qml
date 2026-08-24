import QtQuick
import qs.Commons

Column {
  id: root

  property string title: ""
  property var rows: []
  spacing: Style.spacing.sm

  Text {
    text: root.title
    color: Color.menu.selectedText
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    bottomPadding: Style.space(5)
  }

  Repeater {
    model: root.rows
    Row {
      required property var modelData
      width: root.width
      spacing: Style.spacing.md

      Text {
        width: parent.width * .43
        text: modelData[0]
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width * .57 - parent.spacing
        text: modelData[1]
        color: Color.menu.text
        opacity: .62
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
