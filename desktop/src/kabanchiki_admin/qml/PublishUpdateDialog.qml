import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

AppDialog {
    id: root
    title: qsTr("Publish an update")

    property string apkFile: ""

    function openDialog() {
        apkFile = ""
        versionField.text = ""
        codeField.text = String(backend.latestAndroidVersionCode() + 1)
        notesArea.text = ""
        mandatoryBox.checked = false
        open()
    }

    FileDialog {
        id: apkDialog
        nameFilters: [qsTr("Android package (*.apk)")]
        onAccepted: root.apkFile = selectedFile.toString()
    }

    component FieldLabel: Text {
        font.pixelSize: Theme.fontSizeSm
        font.weight: Font.DemiBold
        color: Theme.textSecondary
    }

    contentItem: ColumnLayout {
        implicitWidth: 440
        spacing: Theme.spacingMd

        Text {
            Layout.fillWidth: true
            text: qsTr("Upload a freshly built APK. Assignees will get a push and an “Update” banner in the app.")
            font.pixelSize: Theme.fontSizeSm
            color: Theme.textSecondary
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            AppButton {
                text: root.apkFile.length > 0 ? qsTr("Change APK…") : qsTr("Choose APK…")
                variant: "secondary"
                onClicked: apkDialog.open()
            }
            Text {
                Layout.fillWidth: true
                text: root.apkFile.length > 0 ? root.apkFile.split("/").pop() : qsTr("no file selected")
                font.pixelSize: Theme.fontSizeSm
                color: root.apkFile.length > 0 ? Theme.success : Theme.textSecondary
                elide: Text.ElideMiddle
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Theme.spacingMd
            rowSpacing: Theme.spacingXs

            FieldLabel { text: qsTr("Version name") }
            FieldLabel { text: qsTr("Version code (integer)") }

            AppTextField {
                id: versionField
                Layout.fillWidth: true
                placeholderText: "1.4.2"
            }
            AppTextField {
                id: codeField
                Layout.fillWidth: true
                placeholderText: "7"
                validator: IntValidator { bottom: 1 }
            }
        }

        FieldLabel { text: qsTr("What's new (assignees will see it)") }
        Rectangle {
            Layout.fillWidth: true
            height: 70
            radius: Theme.radiusSm
            color: Theme.surfaceAlt
            border.width: notesArea.activeFocus ? 2 : 1
            border.color: notesArea.activeFocus ? Theme.accent : Theme.border
            ScrollView {
                anchors.fill: parent
                anchors.margins: 4
                TextArea { id: notesArea; wrapMode: TextArea.Wrap; font.pixelSize: Theme.fontSizeMd; color: Theme.textPrimary; background: null }
            }
        }

        AppCheckBox {
            id: mandatoryBox
            Layout.fillWidth: true
            text: qsTr("Mandatory update")
            description: qsTr("The app will strongly insist on updating before use.")
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton {
                text: backend.busy ? qsTr("Uploading…") : qsTr("Publish")
                enabled: !backend.busy && root.apkFile.length > 0 && versionField.text.length > 0 && codeField.text.length > 0
                onClicked: {
                    backend.publishUpdate({
                        apk_file: root.apkFile,
                        version_name: versionField.text.trim(),
                        version_code: parseInt(codeField.text),
                        notes: notesArea.text,
                        mandatory: mandatoryBox.checked
                    })
                    root.close()
                }
            }
        }
    }
}
