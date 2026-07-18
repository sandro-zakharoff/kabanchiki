import QtQuick
import QtQuick.Layouts

AppDialog {
    id: root
    width: 400
    property string childId: ""
    acceptAction: function() {
        if (passwordField.text.length < 6) return
        backend.setChildPassword(root.childId, passwordField.text)
        root.close()
    }

    function openFor(id, name) {
        childId = id
        title = qsTr("New password for %1").arg(name)
        passwordField.text = ""
        open()
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingMd

        AppTextField {
            id: passwordField
            Layout.fillWidth: true
            placeholderText: qsTr("new password (min. 6 characters)")
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton {
                text: qsTr("Save")
                enabled: passwordField.text.length >= 6
                onClicked: {
                    backend.setChildPassword(root.childId, passwordField.text)
                    root.close()
                }
            }
        }
    }
}
