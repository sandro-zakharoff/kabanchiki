import QtQuick
import QtQuick.Effects

Rectangle {
    id: root
    radius: Theme.radiusMd
    color: Theme.surface
    border.width: 1
    border.color: Theme.border
    property bool shadow: true
    default property alias content: inner.data

    layer.enabled: shadow
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#20000000"
        shadowBlur: 0.4
        shadowVerticalOffset: 4
        shadowHorizontalOffset: 0
    }

    Item {
        id: inner
        anchors.fill: parent
    }
}
