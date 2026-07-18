import QtQuick
import QtQuick.Layouts

AppDialog {
    id: root
    property string message: ""
    property string confirmText: qsTr("Confirm")
    property bool destructive: false
    property var onConfirmed: null

    width: 380
    acceptAction: function() {
        root.close()
        if (root.onConfirmed) root.onConfirmed()
    }

    function openWith(titleText, messageText, callback, destructiveFlag) {
        title = titleText
        message = messageText
        onConfirmed = callback
        destructive = destructiveFlag === true
        open()
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingLg

        Text {
            Layout.fillWidth: true
            text: root.message
            font.pixelSize: Theme.fontSizeMd
            color: Theme.textPrimary
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Item { Layout.fillWidth: true }
            AppButton {
                text: qsTr("Cancel")
                variant: "ghost"
                onClicked: root.close()
            }
            AppButton {
                text: root.confirmText
                variant: root.destructive ? "danger" : "primary"
                onClicked: {
                    root.close()
                    if (root.onConfirmed) root.onConfirmed()
                }
            }
        }
    }
}
