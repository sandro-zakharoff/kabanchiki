import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs as D

// Owner-initiated payout to an assignee: choose an amount from their balance,
// a method (card + optional receipt / cash + confirmation) and a comment.
AppDialog {
    id: root
    title: qsTr("Pay out to assignee")
    width: 460

    property string childId: ""
    property real balance: 0
    property string balanceText: ""
    property string method: "card"
    property string receiptFile: ""

    function amountValue() {
        var v = parseInt(amountField.text, 10)
        return isNaN(v) ? 0 : v
    }
    function canPay() {
        var a = amountValue()
        return a > 0 && a <= root.balance
            && !(root.method === "card" && backend.requireReceiptForCard && root.receiptFile.length === 0)
    }
    function submit() {
        if (!canPay()) return
        var a = amountValue()
        // Exact "all" → pass 0 so the server uses the live balance (no tick race).
        var amt = (a === root.balance) ? 0 : a
        backend.payoutToChild(root.childId, amt, root.method, commentField.text.trim(), root.receiptFile)
        root.close()
    }
    acceptAction: function() { root.submit() }

    function openFor(id, name, bal, balText) {
        childId = id
        balance = bal
        balanceText = balText
        method = "card"
        receiptFile = ""
        subtitle.text = qsTr("%1 · balance %2").arg(name).arg(balText)
        amountField.text = ""
        commentField.text = ""
        open()
    }

    D.FileDialog {
        id: receiptPicker
        title: qsTr("Choose a receipt")
        nameFilters: [qsTr("Receipt (*.pdf *.png *.jpg *.jpeg *.webp)")]
        onAccepted: root.receiptFile = selectedFile.toString()
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingMd

        Text {
            id: subtitle
            font.pixelSize: Theme.fontSizeMd
            color: Theme.textSecondary
        }

        Text { text: qsTr("Amount, acorns"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            AppTextField {
                id: amountField
                Layout.fillWidth: true
                placeholderText: "0"
                validator: IntValidator { bottom: 0 }
            }
            AppButton {
                text: qsTr("All %1").arg(root.balanceText)
                variant: "secondary"
                implicitHeight: 40
                onClicked: amountField.text = String(root.balance)
            }
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

        // card: receipt
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
                    text: root.receiptFile.length > 0 ? root.receiptFile.split("/").pop() : qsTr("No file chosen")
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
            placeholderText: qsTr("e.g. 3 acorns change left with me")
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton {
                text: qsTr("Pay out")
                enabled: root.canPay() && !backend.busy
                onClicked: root.submit()
            }
        }
    }
}
