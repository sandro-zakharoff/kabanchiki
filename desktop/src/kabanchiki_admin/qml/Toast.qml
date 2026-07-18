import QtQuick
import QtQuick.Controls.Basic

Item {
    id: root
    z: 1000

    ListModel { id: toastModel }

    Connections {
        target: backend
        function onToastRequested(message, kind) {
            toastModel.append({ kind: kind, message: message })
        }
    }

    Column {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingSm
        width: 320

        Repeater {
            model: toastModel
            delegate: Card {
                width: 320
                height: msgText.implicitHeight + 28
                radius: Theme.radiusMd
                shadow: true

                Rectangle {
                    width: 4
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    radius: 2
                    color: kind === "error" ? Theme.danger
                        : kind === "success" ? Theme.success
                        : Theme.info
                }

                Text {
                    id: msgText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 20
                    anchors.rightMargin: 14
                    text: message
                    font.pixelSize: Theme.fontSizeMd
                    color: Theme.textPrimary
                    wrapMode: Text.WordWrap
                }

                Timer {
                    interval: 4200
                    running: true
                    onTriggered: toastModel.remove(index)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: toastModel.remove(index)
                }

                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: Theme.animMed } }
            }
        }
    }
}
