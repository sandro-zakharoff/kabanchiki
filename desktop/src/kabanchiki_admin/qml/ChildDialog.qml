import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppDialog {
    id: root
    title: qsTr("New assignee")
    width: 440

    readonly property var palette: ["#CDB1B1", "#8598B5", "#6FA287", "#D99A5B", "#B58BA6", "#C96A5F", "#8C818F", "#7F9E9B"]
    property string selectedColor: palette[0]

    function submit() {
        if (!(nameField.text.trim().length > 0 && usernameField.text.length >= 3
              && passwordField.text.length >= 6)) return
        var crop = avatarPicker.pendingCrop
        backend.createChild(
            usernameField.text, nameField.text.trim(), passwordField.text, root.selectedColor,
            avatarPicker.pendingFile,
            crop ? crop.x : 0, crop ? crop.y : 0, crop ? crop.size : 0)
        root.close()
    }

    acceptAction: function() { root.submit() }

    function openForCreate() {
        nameField.text = ""
        usernameField.text = ""
        passwordField.text = ""
        selectedColor = palette[0]
        avatarPicker.reset("")
        open()
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingMd

        Text { text: qsTr("Photo (optional)"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AvatarPicker {
            id: avatarPicker
            name: nameField.text
            color: root.selectedColor
        }

        Text { text: qsTr("Name (shown in the app)"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: qsTr("e.g. Marko")
        }

        Text { text: qsTr("Login (latin, digits, _)"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField {
            id: usernameField
            Layout.fillWidth: true
            placeholderText: qsTr("e.g. marko")
            validator: RegularExpressionValidator { regularExpression: /[a-z0-9_]{0,24}/ }
        }

        Text { text: qsTr("Password (min. 6 characters)"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField {
            id: passwordField
            Layout.fillWidth: true
            placeholderText: qsTr("password for the account")
        }

        Text { text: qsTr("Avatar color"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        RowLayout {
            spacing: Theme.spacingSm
            Repeater {
                model: root.palette
                delegate: Rectangle {
                    required property string modelData
                    width: 34; height: 34; radius: 17
                    color: modelData
                    border.width: root.selectedColor === modelData ? 3 : 0
                    border.color: Theme.textPrimary
                    scale: root.selectedColor === modelData ? 1.1 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    MouseArea { anchors.fill: parent; onClicked: root.selectedColor = modelData }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton {
                text: qsTr("Create")
                enabled: nameField.text.trim().length > 0
                    && usernameField.text.length >= 3
                    && passwordField.text.length >= 6
                onClicked: root.submit()
            }
        }
    }
}
