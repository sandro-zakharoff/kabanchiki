import QtQuick
import QtQuick.Effects

// Assignee avatar: the photo when one is set, initials on the brand color
// otherwise. The photo is masked to a circle via MultiEffect.
Rectangle {
    id: root
    property string name: ""
    property int size: 32
    property string source: ""

    width: size
    height: size
    radius: size / 2

    Text {
        anchors.centerIn: parent
        visible: !photo.visible
        text: root.name.length > 0 ? root.name.charAt(0).toUpperCase() : "?"
        color: "#FFFFFF"
        font.pixelSize: root.size * 0.45
        font.weight: Font.Bold
    }

    Image {
        id: photo
        anchors.fill: parent
        source: root.source
        visible: root.source.length > 0 && status === Image.Ready
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: 256
        sourceSize.height: 256
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.6
        }
    }

    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: root.radius; color: "#FFFFFF" }
    }
}
