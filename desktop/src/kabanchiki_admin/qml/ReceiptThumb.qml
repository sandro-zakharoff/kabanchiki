import QtQuick

// A receipt tile. Photos get the usual preview; PDFs cannot be previewed
// without a PDF renderer, so they get an honest document tile instead of a
// broken image box — and they open in whatever the system uses for PDFs
// rather than in the in-app Lightbox, which only understands pictures.
Item {
    id: root
    property string source: ""      // thumbnail (photos) — unused for PDFs
    property bool isPdf: false
    signal activated()              // photo tapped: the caller opens the Lightbox
    signal openExternally()         // PDF tapped: hand it to the system viewer

    implicitWidth: 64
    implicitHeight: 64

    ImageThumb {
        anchors.fill: parent
        visible: !root.isPdf
        source: root.source
        onActivated: root.activated()
    }

    Rectangle {
        anchors.fill: parent
        visible: root.isPdf
        radius: Theme.radiusSm
        color: Theme.surfaceAlt
        border.width: 1
        border.color: hover.hovered ? Theme.accent : Theme.border
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        Column {
            anchors.centerIn: parent
            spacing: 2
            Text {
                text: "📄"
                font.pixelSize: Theme.fontSizeLg
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "PDF"
                font.pixelSize: Theme.fontSizeXs
                font.weight: Font.Bold
                color: Theme.textSecondary
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        scale: press.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.animFast } }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: press; onTapped: root.openExternally() }
    }
}
