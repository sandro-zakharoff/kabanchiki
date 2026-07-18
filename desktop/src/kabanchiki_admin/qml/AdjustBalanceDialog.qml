import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Manual balance correction: a bonus (+) or a penalty / fix (−). Both are
// signed ledger entries and require a comment the assignee will see.
AppDialog {
    id: root
    title: qsTr("Adjust balance")
    width: 440

    property string childId: ""
    property int sign: 1   // +1 bonus, -1 penalty

    function amountValue() {
        var v = parseFloat(amountField.text.replace(",", "."))
        return isNaN(v) ? 0 : v
    }
    function canSave() {
        return amountValue() > 0 && noteField.text.trim().length > 0
    }
    function submit() {
        if (!canSave()) return
        backend.adjustBalance(root.childId, root.sign * amountValue(), noteField.text.trim())
        root.close()
    }
    acceptAction: function() { root.submit() }

    function openFor(id, name) {
        childId = id
        sign = 1
        subtitle.text = qsTr("For %1").arg(name)
        amountField.text = ""
        noteField.text = ""
        open()
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingMd

        Text {
            id: subtitle
            font.pixelSize: Theme.fontSizeMd
            color: Theme.textSecondary
        }

        // + bonus / − penalty segment
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Repeater {
                model: [
                    { s: 1,  label: qsTr("Bonus"),   c: Theme.success },
                    { s: -1, label: qsTr("Penalty"), c: Theme.danger }
                ]
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool active: root.sign === modelData.s
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: Theme.radiusSm
                    color: active ? Qt.alpha(modelData.c, 0.14) : Theme.surfaceAlt
                    border.width: active ? 2 : 1
                    border.color: active ? modelData.c : Theme.border
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        text: (modelData.s > 0 ? "+ " : "− ") + modelData.label
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: active ? modelData.c : Theme.textSecondary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sign = modelData.s
                    }
                }
            }
        }

        Text { text: qsTr("Amount, ₴"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField {
            id: amountField
            Layout.fillWidth: true
            placeholderText: "0.00"
            validator: DoubleValidator { bottom: 0; decimals: 2; notation: DoubleValidator.StandardNotation }
        }

        RowLayout {
            spacing: Theme.spacingSm
            Repeater {
                model: [10, 20, 50, 100]
                delegate: Rectangle {
                    required property int modelData
                    height: 30; width: 56; radius: 15
                    color: Theme.surfaceAlt
                    border.width: 1; border.color: Theme.border
                    Text {
                        anchors.centerIn: parent
                        text: (root.sign > 0 ? "+" : "−") + modelData
                        font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: amountField.text = String(modelData)
                    }
                }
            }
        }

        Text { text: qsTr("Comment (required)"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField {
            id: noteField
            Layout.fillWidth: true
            placeholderText: qsTr("e.g. for great behavior / a fix")
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton {
                text: qsTr("Apply")
                enabled: root.canSave()
                onClicked: root.submit()
            }
        }
    }
}
