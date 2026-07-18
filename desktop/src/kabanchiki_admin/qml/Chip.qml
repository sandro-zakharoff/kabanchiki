import QtQuick

Rectangle {
    id: root
    property string text: ""
    property color chipColor: Theme.accent
    property bool filled: false

    implicitHeight: 24
    implicitWidth: label.implicitWidth + 20
    radius: 12
    color: filled ? chipColor : Qt.alpha(chipColor, 0.14)
    border.width: 0

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.filled ? "#FFFFFF" : root.chipColor
        font.pixelSize: Theme.fontSizeXs
        font.weight: Font.DemiBold
    }
}
