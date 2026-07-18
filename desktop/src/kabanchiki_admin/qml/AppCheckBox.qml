import QtQuick
import QtQuick.Controls.Basic

CheckBox {
    id: control
    property string description: ""

    font.pixelSize: Theme.fontSizeMd
    spacing: Theme.spacingSm

    indicator: Rectangle {
        implicitWidth: 22
        implicitHeight: 22
        radius: 7
        y: 2
        color: control.checked ? Theme.accent : Theme.surfaceAlt
        border.width: control.checked ? 0 : 1
        border.color: Theme.border
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        Text {
            anchors.centerIn: parent
            text: "✓"
            color: "#FFFFFF"
            font.pixelSize: 13
            font.bold: true
            visible: control.checked
        }
    }

    contentItem: Column {
        leftPadding: control.indicator.width + control.spacing
        spacing: 2
        Text {
            width: parent.width - parent.leftPadding
            text: control.text
            font.pixelSize: Theme.fontSizeMd
            color: Theme.textPrimary
            wrapMode: Text.WordWrap
        }
        Text {
            width: parent.width - parent.leftPadding
            text: control.description
            font.pixelSize: Theme.fontSizeSm
            color: Theme.textSecondary
            wrapMode: Text.WordWrap
            visible: control.description.length > 0
        }
    }
}
