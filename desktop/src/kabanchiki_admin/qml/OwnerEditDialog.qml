import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Edit an owner's profile. Email doubles as the login.
AppDialog {
    id: root
    title: qsTr("Edit owner")
    property string parentId: ""

    acceptAction: function() { root.save() }

    function openFor(owner) {
        parentId = owner.id
        nameField.text = owner.display_name || ""
        emailField.text = owner.email || ""
        phoneField.text = owner.phone || ""
        noteArea.text = owner.note || ""
        subtitle = owner.email || ""
        open()
    }

    function canSave() {
        return nameField.text.trim().length > 0 && emailField.text.indexOf("@") > 0
    }

    function save() {
        if (!canSave()) return
        backend.updateOwner(root.parentId, nameField.text, emailField.text,
                            phoneField.text, noteArea.text)
        root.close()
    }

    contentItem: ColumnLayout {
        implicitWidth: 400
        spacing: Theme.spacingMd

        Text { text: qsTr("Display name"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField { id: nameField; Layout.fillWidth: true }

        Text { text: qsTr("Email (used to sign in)"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField { id: emailField; Layout.fillWidth: true; placeholderText: "name@example.com" }
        Text {
            visible: emailField.text.length > 0 && emailField.text.indexOf("@") <= 0
            text: qsTr("Enter a valid email")
            font.pixelSize: Theme.fontSizeXs
            color: Theme.danger
        }

        Text { text: qsTr("Phone (optional)"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField { id: phoneField; Layout.fillWidth: true; placeholderText: "+380…" }

        Text { text: qsTr("Note (optional)"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        Rectangle {
            Layout.fillWidth: true
            height: 70
            radius: Theme.radiusSm
            color: Theme.surfaceAlt
            border.width: noteArea.activeFocus ? 2 : 1
            border.color: noteArea.activeFocus ? Theme.accent : Theme.border
            ScrollView {
                anchors.fill: parent
                anchors.margins: 4
                TextArea {
                    id: noteArea
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
                text: qsTr("Save")
                enabled: root.canSave()
                onClicked: root.save()
            }
        }
    }
}
