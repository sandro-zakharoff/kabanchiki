import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string text: ""
    property bool active: false
    property int badge: 0
    signal clicked()

    Layout.fillWidth: true
    height: 40
    radius: Theme.radiusSm
    // NB: never animate from "transparent" (transparent BLACK) — the
    // interpolation passes through dark grey. Use an alpha-zero surface tone.
    color: active ? Theme.accent
         : (hover.containsMouse ? Theme.surfaceAlt : Qt.alpha(Theme.surfaceAlt, 0))
    Behavior on color { ColorAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingMd
        anchors.rightMargin: Theme.spacingMd
        spacing: Theme.spacingSm

        Text {
            text: root.text
            font.pixelSize: Theme.fontSizeMd
            font.weight: Font.DemiBold
            color: root.active ? "#FFFFFF" : Theme.textPrimary
            Layout.fillWidth: true
        }

        Rectangle {
            visible: root.badge > 0
            width: 22; height: 22; radius: 11
            color: root.active ? "#FFFFFF" : Theme.warning
            Text {
                anchors.centerIn: parent
                text: root.badge
                font.pixelSize: Theme.fontSizeXs
                font.weight: Font.Bold
                color: root.active ? Theme.accent : "#FFFFFF"
            }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }

    scale: hover.pressed ? 0.97 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
}
