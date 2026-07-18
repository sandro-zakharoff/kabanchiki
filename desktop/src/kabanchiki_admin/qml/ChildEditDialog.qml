import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppDialog {
    id: root
    title: qsTr("Edit assignee")

    readonly property var palette: ["#CDB1B1", "#8598B5", "#6FA287", "#D99A5B", "#B58BA6", "#C96A5F", "#8C818F", "#7F9E9B"]
    property string childId: ""
    property string selectedColor: palette[0]

    function submit() {
        if (nameField.text.trim().length === 0) return
        var crop = avatarPicker.pendingCrop
        backend.updateChild(root.childId, nameField.text.trim(), root.selectedColor,
            avatarPicker.pendingFile,
            crop ? crop.x : 0, crop ? crop.y : 0, crop ? crop.size : 0,
            avatarPicker.cleared)
        root.close()
    }

    acceptAction: function() { root.submit() }

    function openFor(id, name, color, avatarUrl) {
        childId = id
        nameField.text = name
        selectedColor = color
        avatarPicker.reset(avatarUrl || "")
        open()
    }

    contentItem: ColumnLayout {
        implicitWidth: 380
        spacing: Theme.spacingMd

        Text { text: qsTr("Photo"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AvatarPicker {
            id: avatarPicker
            name: nameField.text
            color: root.selectedColor
        }

        Text { text: qsTr("Name"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField {
            id: nameField
            Layout.fillWidth: true
        }

        Text { text: qsTr("Avatar color"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        Flow {
            Layout.fillWidth: true
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
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedColor = modelData }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton {
                text: qsTr("Save")
                enabled: nameField.text.trim().length > 0
                onClicked: root.submit()
            }
        }
    }
}
