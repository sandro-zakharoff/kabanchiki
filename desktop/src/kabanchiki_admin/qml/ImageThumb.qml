import QtQuick

// A neat, fixed-size photo preview. Fills its box (cover), rounded corners,
// and reveals a "zoom" affordance on hover. Emits activated() on click so the
// caller can open it in the Lightbox.
Rectangle {
    id: root
    property alias source: img.source
    property string caption: ""
    signal activated()

    implicitWidth: 200
    implicitHeight: 140
    radius: Theme.radiusSm
    color: Theme.surfaceAlt
    border.width: 1
    border.color: Theme.border
    clip: true

    Image {
        id: img
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: status === Image.Ready
    }

    // Loading / broken placeholder.
    Text {
        anchors.centerIn: parent
        visible: img.status !== Image.Ready
        text: img.status === Image.Loading ? "…" : "🖼"
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeLg
    }

    // Hover scrim + magnifier hint.
    Rectangle {
        anchors.fill: parent
        color: "#00000000"
        radius: parent.radius
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        gradient: Gradient {
            GradientStop { position: 0.5; color: "#00000000" }
            GradientStop { position: 1.0; color: "#66000000" }
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8
            text: "⌕ " + qsTr("Zoom")
            color: "#FFFFFF"
            font.pixelSize: Theme.fontSizeXs
            font.weight: Font.DemiBold
        }
    }

    scale: press.pressed ? 0.98 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast } }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: press; onTapped: if (img.status === Image.Ready) root.activated() }
}
