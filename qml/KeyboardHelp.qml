import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  signal closeRequested()

  readonly property var browserKeys: [
    ["h j k l / arrows", "Move selection"],
    ["Enter / o", "Open selection"],
    ["Space", "Quick Look"],
    ["gg / G", "First / last item"],
    ["Ctrl+U / Ctrl+D", "Half-page scroll"],
    ["Backspace", "Parent folder"],
    ["H / L", "Back / forward"],
    ["gh / gp", "Home / Pictures"],
    ["/ / Ctrl+F", "Filter folder"],
    ["c", "Fuzzy directory jump"],
    ["Ctrl+L", "Edit location"],
    [". / Ctrl+H", "Toggle hidden files"],
    ["y", "Copy path"],
    ["r / R", "Rename / refresh"],
    ["d", "Move to Trash (confirm)"],
    ["s", "Show / hide sidebar"],
    ["Shift+S", "Browser settings"],
    ["+ / -", "Thumbnail size"],
    ["Shift + / Shift -", "Grid gap"],
    ["F11", "Fullscreen"],
    ["q / Escape", "Close browser"],
    ["?", "This help"]
  ]

  readonly property var quickKeys: [
    ["q / Escape", "Close Quick Look"],
    ["Space", "Close image / play video"],
    ["[ / ]", "Previous / next media"],
    ["Shift+← / Shift+→", "Previous / next media"],
    ["← → / h l", "Previous/next image; seek video"],
    ["j k l", "Video −10s / play / +5s"],
    ["m", "Mute video"],
    ["f / 0", "Fit image"],
    ["1", "Image at 100%"],
    ["+ / -", "Zoom image"],
    ["mouse wheel", "Zoom around pointer"],
    ["mouse drag", "Pan a zoomed image"],
    ["c / Tab", "Show / hide controls"],
    ["?", "This help"]
  ]

  Rectangle { anchors.fill: parent; color: Color.menu.scrim }
  MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }

  BorderSurface {
    id: card
    width: Math.min(parent.width - Style.space(32), Style.space(820))
    height: Math.min(parent.height - Style.space(32), Style.space(650))
    anchors.centerIn: parent
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
    radius: Style.cornerRadius
    padding: Style.space(20)

    MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(20)
      spacing: Style.spacing.lg

      Row {
        width: parent.width
        Text { width: parent.width - closeButton.width; text: "KEYBOARD REFERENCE"; color: Color.menu.text; font.family: Style.font.family; font.pixelSize: Style.font.title }
        ToolbarButton { id: closeButton; label: "Close"; onClicked: root.closeRequested() }
      }

      Row {
        width: parent.width
        height: parent.height - Style.space(48)
        spacing: Style.space(28)

        KeyColumn { width: (parent.width - parent.spacing) / 2; title: "BROWSER"; rows: root.browserKeys }
        KeyColumn { width: (parent.width - parent.spacing) / 2; title: "QUICK LOOK"; rows: root.quickKeys }
      }
    }
  }
}
