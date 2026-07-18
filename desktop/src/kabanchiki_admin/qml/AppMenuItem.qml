import QtQuick
import QtQuick.Controls.Basic

MenuItem {
    id: control
    property bool danger: false

    implicitHeight: 34

    contentItem: Text {
        leftPadding: 10
        text: control.text
        font.pixelSize: Theme.fontSizeSm
        color: !control.enabled
            ? Theme.textSecondary
            : (control.danger ? Theme.danger : Theme.textPrimary)
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        radius: Theme.radiusSm - 4
        color: control.highlighted ? Theme.surfaceAlt : "#FFFFFF"
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}
