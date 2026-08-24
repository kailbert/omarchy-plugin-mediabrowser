import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false
  property string title: "COMMANDS"
  property var commands: []
  property string query: ""
  property var matches: []
  property int selectedIndex: 0

  signal invoked(string command)
  signal closeRequested()

  function show(titleText, values) {
    title = titleText
    commands = values || []
    query = ""
    selectedIndex = 0
    rebuild()
    opened = true
    Qt.callLater(function() { field.forceActiveFocus() })
  }

  function close() { opened = false; closeRequested() }

  function rebuild() {
    var needle = query.trim().toLocaleLowerCase()
    matches = commands.filter(function(command) {
      return command.enabled !== false && (!needle || (command.label + " " + (command.detail || "") + " " + (command.key || "")).toLocaleLowerCase().indexOf(needle) >= 0)
    })
    selectedIndex = matches.length ? Math.max(0, Math.min(selectedIndex, matches.length - 1)) : 0
  }

  function choose() {
    if (!matches.length) return
    var command = matches[selectedIndex].id
    opened = false
    invoked(command)
  }

  visible: opened
  z: 108

  Rectangle { anchors.fill: parent; color: Color.menu.scrim }
  MouseArea { anchors.fill: parent; onClicked: root.close() }

  BorderSurface {
    width: Math.min(parent.width - Style.space(32), Style.space(620))
    height: Math.min(parent.height - Style.space(40), Style.space(560))
    anchors.centerIn: parent
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
    radius: Style.cornerRadius
    MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

    Column {
      anchors.fill: parent; anchors.margins: Style.space(16); spacing: Style.spacing.md
      Text { text: root.title; color: Color.menu.text; opacity: .55; font.family: Style.font.family; font.pixelSize: Style.font.caption }
      TextField {
        id: field
        width: parent.width
        placeholderText: "Type a command…"
        text: root.query
        onTextChanged: { root.query = text; root.selectedIndex = 0; root.rebuild() }
        onAccepted: root.choose()
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
          else if (event.key === Qt.Key_Down || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_N)) {
            root.selectedIndex = Math.min(root.matches.length - 1, root.selectedIndex + 1); list.positionViewAtIndex(root.selectedIndex, ListView.Contain); event.accepted = true
          } else if (event.key === Qt.Key_Up || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_P)) {
            root.selectedIndex = Math.max(0, root.selectedIndex - 1); list.positionViewAtIndex(root.selectedIndex, ListView.Contain); event.accepted = true
          }
        }
      }
      Rectangle { width: parent.width; height: Math.max(1, Style.normalBorderWidth); color: Color.menu.border; opacity: .35 }
      ListView {
        id: list
        width: parent.width; height: parent.height - field.height - Style.space(52)
        clip: true; spacing: Style.spacing.xs; model: root.matches
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: list.width; height: Style.space(48); radius: Style.cornerRadius
          color: index === root.selectedIndex ? Style.selectedFillFor(Color.menu.text, Color.menu.selectedText)
                                                : (mouse.containsMouse ? Style.hoverFillFor(Color.menu.text, Color.menu.selectedText) : "transparent")
          Text { anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; width: Style.space(46); text: modelData.key || ""; color: index === root.selectedIndex ? Color.menu.selectedText : Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
          Column {
            anchors.left: parent.left; anchors.leftMargin: Style.space(62); anchors.right: parent.right; anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
            Text { width: parent.width; text: modelData.label; color: index === root.selectedIndex ? Color.menu.selectedText : Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.body; elide: Text.ElideRight }
            Text { width: parent.width; visible: text.length > 0; text: modelData.detail || ""; color: index === root.selectedIndex ? Color.menu.selectedText : Color.menu.text; opacity: .48; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
          }
          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: { root.selectedIndex = index; root.choose() }
          }
        }
      }
    }
  }
}
