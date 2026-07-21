import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Personal balances: a card per assignee (balance + weekly/monthly earnings and
// a manual correction), and the full ledger below, filterable by assignee.
Item {
    id: root
    property string selectedChild: ""

    function kindMeta(kind) {
        switch (kind) {
        case "task":       return { icon: "✓", c: Theme.success }
        case "job":        return { icon: "⏱", c: Theme.accent }
        case "bonus":      return { icon: "★", c: Theme.warning }
        case "adjustment": return { icon: "±", c: Theme.info }
        case "withdrawal": return { icon: "↑", c: Theme.danger }
        case "reversal":   return { icon: "↺", c: Theme.textSecondary }
        }
        return { icon: "•", c: Theme.textSecondary }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: qsTr("Balances")
                font.pixelSize: Theme.fontSizeXl
                font.weight: Font.Bold
                color: Theme.textPrimary
            }
            // What an acorn is worth, said once on the page where money lives.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 24
                implicitWidth: rateRow.implicitWidth + 20
                radius: 12
                color: Qt.alpha(Theme.accentSoft, 0.35)

                Row {
                    id: rateRow
                    anchors.centerIn: parent
                    spacing: 4
                    AcornAmount {
                        text: "1"
                        fontSize: Theme.fontSizeXs
                        color: Theme.accentDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: qsTr("= 1 hryvnia")
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Font.DemiBold
                        color: Theme.accentDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        // ---------------------------------------- balance cards
        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            Repeater {
                model: backend.balancesModel
                delegate: Card {
                    id: bCard
                    width: 300
                    implicitHeight: bCol.implicitHeight + Theme.spacingLg
                    readonly property bool selected: root.selectedChild === model.childId

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusMd
                        color: "transparent"
                        border.width: bCard.selected ? 2 : 0
                        border.color: Qt.alpha(Theme.accent, 0.5)
                    }

                    ColumnLayout {
                        id: bCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingMd
                        spacing: Theme.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm
                            Avatar { name: model.name; color: model.color; size: 40; source: model.avatarUrl }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: model.name
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.DemiBold
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: qsTr("week %1 · month %2").arg(model.weekText).arg(model.monthText)
                                    font.pixelSize: Theme.fontSizeXs
                                    color: Theme.textSecondary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        AcornAmount {
                            text: model.balanceText
                            fontSize: Theme.fontSizeXxl
                            fontWeight: Font.Bold
                            fontFamily: "Consolas"
                            color: model.balance > 0 ? Theme.accent : Theme.textSecondary
                            Layout.topMargin: Theme.spacingXs
                        }

                        AppButton {
                            text: qsTr("Pay out")
                            Layout.fillWidth: true
                            Layout.topMargin: Theme.spacingXs
                            implicitHeight: 34
                            enabled: model.balance > 0
                            onClicked: payoutRef.openFor(model.childId, model.name, model.balance, backend.acornWords(model.balance))
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm
                            AppButton {
                                text: qsTr("Adjust")
                                variant: "secondary"
                                implicitHeight: 32
                                onClicked: balanceAdjustRef.openFor(model.childId, model.name)
                            }
                            Item { Layout.fillWidth: true }
                            AppButton {
                                text: bCard.selected ? qsTr("All history") : qsTr("History")
                                variant: "ghost"
                                implicitHeight: 32
                                onClicked: {
                                    root.selectedChild = bCard.selected ? "" : model.childId
                                    backend.selectLedgerChild(root.selectedChild)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---------------------------------------- ledger feed
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingSm
            Text {
                text: qsTr("Operations")
                font.pixelSize: Theme.fontSizeLg
                font.weight: Font.Bold
                color: Theme.textPrimary
            }
            Item { Layout.fillWidth: true }
            AppButton {
                visible: root.selectedChild.length > 0
                text: qsTr("Show all")
                variant: "ghost"
                implicitHeight: 30
                onClicked: { root.selectedChild = ""; backend.selectLedgerChild("") }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingXs
                spacing: 0

                // empty state
                Item {
                    visible: ledgerList.count === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("No operations yet")
                        font.pixelSize: Theme.fontSizeMd
                        color: Theme.textSecondary
                    }
                }

                ListView {
                    id: ledgerList
                    visible: count > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: backend.ledgerModel
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        id: ledgerRow
                        width: ledgerList.width
                        height: 58
                        readonly property var meta: root.kindMeta(model.kind)
                        // A transaction produced by a task/job/payout/bonus can
                        // open that entity's full story.
                        readonly property bool traceable:
                            model.sourceEntity.length > 0 && model.sourceId.length > 0
                        color: traceable && ledgerHover.containsMouse ? Theme.surfaceAlt : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        MouseArea {
                            id: ledgerHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: ledgerRow.traceable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (ledgerRow.traceable)
                                    backend.openTimeline(model.sourceEntity, model.sourceId, model.childName)
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSm
                            anchors.rightMargin: Theme.spacingSm
                            spacing: Theme.spacingSm

                            Rectangle {
                                width: 34; height: 34; radius: 17
                                color: Qt.alpha(meta.c, 0.14)
                                Text { anchors.centerIn: parent; text: meta.icon; font.pixelSize: 16; color: meta.c }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: model.note.length > 0 ? (model.title + " · " + model.note) : model.title
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.DemiBold
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: (root.selectedChild.length > 0 ? "" : (model.childName + " · "))
                                        + model.timeText
                                        + (model.actorName.length > 0 ? (" · " + model.actorName) : "")
                                    font.pixelSize: Theme.fontSizeXs
                                    color: Theme.textSecondary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            AcornAmount {
                                text: model.amountText
                                fontSize: Theme.fontSizeMd
                                fontWeight: Font.Bold
                                fontFamily: "Consolas"
                                color: model.positive ? Theme.success : Theme.danger
                            }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width; height: 1
                            color: Theme.border
                        }
                    }
                }
            }
        }
    }
}
