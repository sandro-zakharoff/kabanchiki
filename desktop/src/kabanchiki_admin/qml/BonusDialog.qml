import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppDialog {
    id: root
    title: editBonusId.length > 0 ? qsTr("Edit bonus") : qsTr("Give a bonus")

    property string childId: ""
    property string editBonusId: ""
    acceptAction: function() {
        if (!(amountField.text.length > 0 && parseFloat(amountField.text.replace(",", ".")) > 0)) return
        var amount = parseFloat(amountField.text.replace(",", "."))
        if (root.editBonusId.length > 0) backend.updateBonus(root.editBonusId, amount, noteField.text)
        else backend.giveBonus(root.childId, amount, noteField.text)
        root.close()
    }

    function openFor(id, name) {
        editBonusId = ""
        childId = id
        subtitle.text = qsTr("A reward for %1").arg(name)
        amountField.text = ""
        noteField.text = ""
        open()
    }

    function openForEdit(bonusId, amount, note) {
        editBonusId = bonusId
        childId = ""
        subtitle.text = qsTr("Edit the reward amount or note")
        amountField.text = String(amount)
        noteField.text = note
        open()
    }

    contentItem: ColumnLayout {
        implicitWidth: 380
        spacing: Theme.spacingMd

        Text {
            id: subtitle
            font.pixelSize: Theme.fontSizeMd
            color: Theme.textSecondary
        }

        Text { text: qsTr("Amount, ₴"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField {
            id: amountField
            Layout.fillWidth: true
            placeholderText: "0.00"
            validator: DoubleValidator { bottom: 0; decimals: 2; notation: DoubleValidator.StandardNotation }
        }

        // Quick amount chips.
        RowLayout {
            spacing: Theme.spacingSm
            Repeater {
                model: [10, 20, 50, 100]
                delegate: Rectangle {
                    required property int modelData
                    height: 30; width: 56; radius: 15
                    color: Theme.surfaceAlt
                    border.width: 1; border.color: Theme.border
                    Text { anchors.centerIn: parent; text: "+" + modelData; font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textPrimary }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: amountField.text = String(modelData)
                    }
                }
            }
        }

        Text { text: qsTr("Note (the assignee will see it)"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField {
            id: noteField
            Layout.fillWidth: true
            placeholderText: qsTr("e.g. for great behavior")
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton {
                text: root.editBonusId.length > 0 ? qsTr("Save") : qsTr("Grant bonus")
                enabled: amountField.text.length > 0 && parseFloat(amountField.text.replace(",", ".")) > 0
                onClicked: {
                    var amount = parseFloat(amountField.text.replace(",", "."))
                    if (root.editBonusId.length > 0) {
                        backend.updateBonus(root.editBonusId, amount, noteField.text)
                    } else {
                        backend.giveBonus(root.childId, amount, noteField.text)
                    }
                    root.close()
                }
            }
        }
    }
}
