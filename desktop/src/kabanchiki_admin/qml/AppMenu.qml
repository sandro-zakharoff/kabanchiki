import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects

Menu {
    id: control
    topPadding: 6
    bottomPadding: 6

    background: Rectangle {
        implicitWidth: 220
        color: Theme.surface
        radius: Theme.radiusSm
        border.width: 1
        border.color: Theme.border

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#28000000"
            shadowBlur: 0.5
            shadowVerticalOffset: 6
        }
    }

    delegate: AppMenuItem {}

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast }
        NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: Theme.animFast; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.animFast }
    }
}
