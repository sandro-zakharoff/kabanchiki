import QtQuick
import QtQuick.Controls.Basic

Button {
    id: control
    property string variant: "primary" // primary | secondary | danger | ghost
    property bool small: false

    implicitHeight: small ? 32 : 38
    implicitWidth: Math.max(small ? 72 : 92, label.implicitWidth + (small ? 24 : 32))
    font.pixelSize: small ? Theme.fontSizeSm : Theme.fontSizeMd
    font.weight: Font.DemiBold

    readonly property color baseColor: {
        if (variant === "primary") return Theme.accent
        if (variant === "danger") return Theme.danger
        if (variant === "ghost") return "#00FFFFFF"
        return Theme.surface
    }
    readonly property color hoverColor: {
        if (variant === "primary") return Qt.lighter(Theme.accent, 1.12)
        if (variant === "danger") return Qt.lighter(Theme.danger, 1.10)
        return Theme.surfaceAlt
    }
    readonly property color pressColor: {
        if (variant === "primary") return Qt.darker(Theme.accent, 1.12)
        if (variant === "danger") return Qt.darker(Theme.danger, 1.12)
        return Theme.surfacePressed
    }
    readonly property color fgColor: (variant === "primary" || variant === "danger") ? "#FFFFFF" : Theme.textPrimary

    background: Rectangle {
        radius: Theme.radiusSm
        color: !control.enabled
            ? (control.variant === "ghost" ? "#00FFFFFF" : Theme.surfaceAlt)
            : (control.pressed ? control.pressColor
                : (control.hovered ? control.hoverColor : control.baseColor))
        border.width: (control.variant === "secondary" || control.variant === "ghost") ? 1 : 0
        border.color: control.hovered ? Qt.darker(Theme.border, 1.08) : Theme.border
        Behavior on color { ColorAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: Theme.animMed } }
    }

    contentItem: Text {
        id: label
        text: control.text
        color: control.enabled ? control.fgColor : Theme.textSecondary
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    scale: control.pressed ? 0.97 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
