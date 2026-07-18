import QtQuick
import QtQuick.Controls.Basic

Dialog {
    id: control

    modal: true
    anchors.centerIn: parent
    padding: 24
    clip: true

    // Optional subtitle shown under the title.
    property string subtitle: ""

    // Optional: primary action triggered by Enter (Esc closes via closePolicy).
    // Skipped while a multiline editor has focus so Enter still inserts a line.
    property var acceptAction: null

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: control.opened && control.acceptAction !== null
                 && !(control.Window.activeFocusItem
                      && control.Window.activeFocusItem instanceof TextArea)
        onActivated: control.acceptAction()
    }

    // Never grow beyond the window; long content scrolls inside the dialog.
    readonly property int maxContentHeight:
        parent ? Math.max(240, parent.height - 160) : 560

    width: Math.min(implicitWidth, parent ? parent.width - 80 : 640)
    height: Math.min(implicitHeight, parent ? parent.height - 80 : 720)

    Overlay.modal: Rectangle {
        color: "#3A000000"
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function(wheel) { wheel.accepted = true }
        }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMed; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.animMed; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.animFast }
    }

    // No layer shadow here: the dialog's rectangular clip cuts a blurred
    // shadow along the edges but leaves it in the rounded-corner notches,
    // which showed up as dark blobs. The dimmed overlay separates the
    // dialog from the page well enough on its own.
    background: Rectangle {
        color: Theme.surface
        radius: Theme.radiusLg
        border.width: 1
        border.color: Theme.border

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function(wheel) { wheel.accepted = true }
        }
    }

    header: Item {
        implicitHeight: control.title.length > 0 ? (control.subtitle.length > 0 ? 74 : 58) : 0
        visible: control.title.length > 0

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 4
            spacing: 2
            Text {
                width: parent.width
                text: control.title
                font.pixelSize: Theme.fontSizeXl
                font.weight: Font.Bold
                color: Theme.textPrimary
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: control.subtitle.length > 0
                text: control.subtitle
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
                elide: Text.ElideRight
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.border
            opacity: 0.6
        }
    }
}
