import QtQuick

Rectangle {
    id: root
    property string text: ""
    property color chipColor: Theme.accent
    property bool filled: false
    // Render `text` as an amount of acorns (number + mark) rather than plain
    // text. The mark follows the chip's own colour, so it reads as part of the
    // pill instead of a sticker on top of it.
    property bool acorn: false
    property string suffix: ""

    readonly property color contentColor: filled ? "#FFFFFF" : chipColor

    implicitHeight: 24
    implicitWidth: content.implicitWidth + 20
    radius: 12
    color: filled ? chipColor : Qt.alpha(chipColor, 0.14)
    border.width: 0

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 0

        Text {
            visible: !root.acorn
            text: root.text
            color: root.contentColor
            font.pixelSize: Theme.fontSizeXs
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }

        AcornAmount {
            visible: root.acorn
            text: root.text
            suffix: root.suffix
            // On a filled pill the brown mark would disappear — tint it instead.
            mono: root.filled
            color: root.contentColor
            fontSize: Theme.fontSizeXs
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
