import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Small dialog that collects a note and runs a callback with it.
AppDialog {
    id: root
    width: 420

    property string confirmText: qsTr("OK")
    property string placeholder: ""
    property bool destructive: false
    property var onConfirmed: null
    // Ctrl-free flow: Enter inside the TextArea keeps inserting newlines
    // (AppDialog skips the shortcut there); Enter elsewhere confirms.
    acceptAction: function() {
        root.close()
        if (root.onConfirmed) root.onConfirmed(noteField.text)
    }

    function openWith(titleText, placeholderText, confirmLabel, cb, destructiveFlag) {
        title = titleText
        placeholder = placeholderText
        confirmText = confirmLabel
        onConfirmed = cb
        destructive = destructiveFlag === true
        noteField.text = ""
        open()
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingMd

        Rectangle {
            Layout.fillWidth: true
            height: 90
            radius: Theme.radiusSm
            color: Theme.surfaceAlt
            border.width: noteField.activeFocus ? 2 : 1
            border.color: noteField.activeFocus ? Theme.accent : Theme.border
            ScrollView {
                anchors.fill: parent
                anchors.margins: 4
                TextArea {
                    id: noteField
                    placeholderText: root.placeholder
                    wrapMode: TextArea.Wrap
                    font.pixelSize: Theme.fontSizeMd
                    color: Theme.textPrimary
                    background: null
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton {
                text: root.confirmText
                variant: root.destructive ? "danger" : "primary"
                onClicked: {
                    root.close()
                    if (root.onConfirmed) root.onConfirmed(noteField.text)
                }
            }
        }
    }
}
