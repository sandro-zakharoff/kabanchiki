import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: control
    implicitHeight: 40
    color: Theme.textPrimary
    font.pixelSize: Theme.fontSizeMd
    selectionColor: Theme.accent
    placeholderTextColor: Theme.textSecondary
    leftPadding: 12
    rightPadding: 12
    selectByMouse: true

    background: Rectangle {
        radius: Theme.radiusSm
        color: Theme.surfaceAlt
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Theme.accent : Theme.border
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
    }
}
