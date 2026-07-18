import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Payout register: every withdrawal with its lifecycle, filters and actions.
Item {
    id: root

    function statusMeta(s) {
        switch (s) {
        case "requested": return { label: qsTr("Requested"), c: Theme.warning }
        case "approved":  return { label: qsTr("Approved"),  c: Theme.info }
        case "paid":      return { label: qsTr("Paid, awaiting confirmation"), c: Theme.accent }
        case "confirmed": return { label: qsTr("Confirmed"), c: Theme.success }
        case "rejected":  return { label: qsTr("Declined"),  c: Theme.danger }
        }
        return { label: s, c: Theme.textSecondary }
    }

    function applyFilters() {
        backend.setWithdrawalFilter(
            childFilter.currentIndex > 0 ? childFilter.model[childFilter.currentIndex].id : "",
            statusFilter.model[statusFilter.currentIndex].value,
            methodFilter.model[methodFilter.currentIndex].value,
            periodFilter.model[periodFilter.currentIndex].value)
    }

    function receiptUrls(items) {
        var urls = []
        for (var i = 0; i < items.length; i++) urls.push(items[i].url)
        return urls
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        Text {
            text: qsTr("Withdrawals")
            font.pixelSize: Theme.fontSizeXl
            font.weight: Font.Bold
            color: Theme.textPrimary
        }

        // ---------------------------------------- filters
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            AppComboBox {
                id: childFilter
                Layout.preferredWidth: 170
                textRole: "name"
                model: [{ name: qsTr("Everyone"), id: "" }].concat(backend.childOptions)
                onActivated: root.applyFilters()
            }
            AppComboBox {
                id: statusFilter
                Layout.preferredWidth: 150
                textRole: "label"
                model: [
                    { label: qsTr("Any status"), value: "" },
                    { label: qsTr("Requested"),  value: "requested" },
                    { label: qsTr("Approved"),   value: "approved" },
                    { label: qsTr("Paid"),       value: "paid" },
                    { label: qsTr("Confirmed"),  value: "confirmed" },
                    { label: qsTr("Declined"),   value: "rejected" }
                ]
                onActivated: root.applyFilters()
            }
            AppComboBox {
                id: methodFilter
                Layout.preferredWidth: 130
                textRole: "label"
                model: [
                    { label: qsTr("Any method"), value: "" },
                    { label: qsTr("To card"),    value: "card" },
                    { label: qsTr("Cash"),       value: "cash" }
                ]
                onActivated: root.applyFilters()
            }
            AppComboBox {
                id: periodFilter
                Layout.preferredWidth: 130
                textRole: "label"
                model: [
                    { label: qsTr("All time"), value: "" },
                    { label: qsTr("Today"),    value: "today" },
                    { label: qsTr("7 days"),   value: "7d" },
                    { label: qsTr("30 days"),  value: "30d" }
                ]
                onActivated: root.applyFilters()
            }
            Item { Layout.fillWidth: true }
        }

        // ---------------------------------------- list
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: wList.count === 0
                text: qsTr("No withdrawals")
                font.pixelSize: Theme.fontSizeMd
                color: Theme.textSecondary
            }

            ListView {
                id: wList
                anchors.fill: parent
                clip: true
                spacing: Theme.spacingMd
                model: backend.withdrawalsModel
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Card {
                    width: wList.width
                    implicitHeight: wCol.implicitHeight + Theme.spacingLg
                    readonly property var meta: root.statusMeta(model.status)
                    readonly property var receiptList: model.receiptsVar || []

                    ColumnLayout {
                        id: wCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingMd
                        spacing: Theme.spacingSm

                        // header: who, amount, status
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm
                            Avatar { name: model.childName; color: model.childColor; size: 38; source: model.childAvatarUrl }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: model.childName
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.DemiBold
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: qsTr("requested %1").arg(model.requestedAtText)
                                    font.pixelSize: Theme.fontSizeXs
                                    color: Theme.textSecondary
                                }
                            }
                            Text {
                                text: model.amountText
                                font.pixelSize: Theme.fontSizeXl
                                font.weight: Font.Bold
                                font.family: "Consolas"
                                color: Theme.textPrimary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm
                            Chip { text: meta.label; chipColor: meta.c; filled: true }
                            Chip {
                                visible: model.method.length > 0
                                text: model.method === "card" ? qsTr("To card") : qsTr("Cash")
                                chipColor: Theme.textSecondary
                            }
                            Item { Layout.fillWidth: true }
                        }

                        // timeline / notes
                        Text {
                            visible: model.comment.length > 0
                            text: qsTr("Comment: %1").arg(model.comment)
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: model.status === "rejected" && model.rejectReason.length > 0
                            text: qsTr("Reason: %1").arg(model.rejectReason)
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.danger
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: model.paidAtText.length > 0 || model.confirmedAtText.length > 0
                            text: (model.paidAtText.length > 0 ? qsTr("paid %1").arg(model.paidAtText) : "")
                                + (model.confirmedAtText.length > 0 ? ("  ·  " + qsTr("confirmed %1").arg(model.confirmedAtText)) : "")
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textSecondary
                        }

                        // receipts
                        Flow {
                            visible: receiptList.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: Theme.spacingXs
                            spacing: Theme.spacingSm
                            Repeater {
                                model: receiptList
                                delegate: ImageThumb {
                                    required property var modelData
                                    required property int index
                                    width: 64; height: 64
                                    source: modelData.thumbUrl || modelData.url
                                    onActivated: lightboxRef.showList(root.receiptUrls(receiptList), index)
                                }
                            }
                        }

                        // actions
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Theme.spacingXs
                            spacing: Theme.spacingSm
                            Item { Layout.fillWidth: true }
                            AppButton {
                                visible: model.status === "requested"
                                text: qsTr("Decline")
                                variant: "danger"
                                implicitHeight: 34
                                onClicked: noteRef.openWith(
                                    qsTr("Decline withdrawal"),
                                    qsTr("Reason (the assignee will see it)"),
                                    qsTr("Decline"),
                                    function(reason) { backend.withdrawalReject(model.wId, reason) },
                                    true)
                            }
                            AppButton {
                                visible: model.status === "requested"
                                text: qsTr("Approve")
                                implicitHeight: 34
                                onClicked: backend.withdrawalApprove(model.wId)
                            }
                            AppButton {
                                visible: model.status === "approved"
                                text: qsTr("Pay…")
                                implicitHeight: 34
                                onClicked: withdrawalPayRef.openFor(model.wId, model.childName, model.amountText)
                            }
                        }
                    }
                }
            }
        }
    }
}
