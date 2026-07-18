import QtQuick
import QtQuick.Controls.Basic

ComboBox {
    id: control
    implicitHeight: 40
    font.pixelSize: Theme.fontSizeMd

    background: Rectangle {
        radius: Theme.radiusSm
        color: Theme.surfaceAlt
        border.width: (control.activeFocus || control.down) ? 2 : 1
        border.color: (control.activeFocus || control.down) ? Theme.accent : Theme.border
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
    }

    contentItem: Text {
        leftPadding: 12
        rightPadding: 32
        text: control.displayText
        font: control.font
        color: Theme.textPrimary
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        x: control.width - width - 12
        anchors.verticalCenter: parent.verticalCenter
        text: "▾"
        font.pixelSize: Theme.fontSizeMd
        color: Theme.textSecondary
        rotation: control.popup.visible ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.animFast } }
    }

    delegate: ItemDelegate {
        id: item
        required property var model
        required property int index
        width: control.width - 8
        height: 34
        x: 4

        contentItem: Text {
            text: item.model[control.textRole] !== undefined ? item.model[control.textRole] : item.model.modelData
            font.pixelSize: Theme.fontSizeMd
            color: Theme.textPrimary
            verticalAlignment: Text.AlignVCenter
            leftPadding: 8
        }

        background: Rectangle {
            radius: Theme.radiusSm - 4
            color: item.highlighted || item.hovered ? Theme.surfaceAlt : "#FFFFFF"
        }

        highlighted: control.highlightedIndex === index
    }

    popup: Popup {
        y: control.height + 4
        width: control.width
        padding: 4

        background: Rectangle {
            color: Theme.surface
            radius: Theme.radiusSm
            border.width: 1
            border.color: Theme.border
        }

        contentItem: ListView {
            clip: true
            implicitHeight: Math.min(contentHeight, 320)
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast }
        }
    }
}
