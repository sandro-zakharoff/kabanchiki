import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs as D

// Record a payout: to card (optionally attach a receipt) or in cash (the
// assignee then confirms receipt). A free comment can accompany either.
AppDialog {
    id: root
    title: qsTr("Pay out")
    width: 460

    property string wId: ""
    property string method: "card"     // 'card' | 'cash'
    property string receiptFile: ""

    function submit() {
        if (root.method === "card")
            backend.withdrawalPayCard(root.wId, commentField.text.trim(), root.receiptFile)
        else
            backend.withdrawalPayCash(root.wId, commentField.text.trim())
        root.close()
    }
    acceptAction: function() { root.submit() }

    function openFor(id, name, amountText) {
        wId = id
        method = "card"
        receiptFile = ""
        subtitle.text = qsTr("%1 · %2").arg(name).arg(amountText)
        commentField.text = ""
        open()
    }

    D.FileDialog {
        id: receiptPicker
        title: qsTr("Choose a receipt")
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.webp)")]
        onAccepted: root.receiptFile = selectedFile.toString()
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingMd

        Text {
            id: subtitle
            font.pixelSize: Theme.fontSizeMd
            color: Theme.textSecondary
        }

        // method segment
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Repeater {
                model: [
                    { m: "card", label: qsTr("To card") },
                    { m: "cash", label: qsTr("Cash") }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: root.method === modelData.m
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: Theme.radiusSm
                    color: active ? Qt.alpha(Theme.accent, 0.14) : Theme.surfaceAlt
                    border.width: active ? 2 : 1
                    border.color: active ? Theme.accent : Theme.border
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: active ? Theme.accent : Theme.textSecondary
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.method = modelData.m }
                }
            }
        }

        // card: receipt attachment
        ColumnLayout {
            visible: root.method === "card"
            Layout.fillWidth: true
            spacing: Theme.spacingXs
            Text {
                text: backend.requireReceiptForCard ? qsTr("Receipt (required)") : qsTr("Receipt (optional)")
                font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                AppButton {
                    text: root.receiptFile.length > 0 ? qsTr("Change file") : qsTr("Attach receipt")
                    variant: "secondary"
                    onClicked: receiptPicker.open()
                }
                Text {
                    Layout.fillWidth: true
                    text: root.receiptFile.length > 0
                        ? root.receiptFile.split("/").pop() : qsTr("No file chosen")
                    elide: Text.ElideMiddle
                    font.pixelSize: Theme.fontSizeSm
                    color: root.receiptFile.length > 0 ? Theme.textPrimary : Theme.textSecondary
                }
                AppButton {
                    visible: root.receiptFile.length > 0
                    text: qsTr("Remove"); variant: "ghost"
                    onClicked: root.receiptFile = ""
                }
            }
        }

        // cash hint
        Text {
            visible: root.method === "cash"
            Layout.fillWidth: true
            text: qsTr("The assignee will get a request to confirm they received the cash.")
            font.pixelSize: Theme.fontSizeXs
            color: Theme.textSecondary
            wrapMode: Text.WordWrap
        }

        Text { text: qsTr("Comment (optional)"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField {
            id: commentField
            Layout.fillWidth: true
            placeholderText: qsTr("e.g. 3 ₴ change left with me")
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton {
                text: qsTr("Confirm payout")
                enabled: !backend.busy
                    && !(root.method === "card" && backend.requireReceiptForCard && root.receiptFile.length === 0)
                onClicked: root.submit()
            }
        }
    }
}
