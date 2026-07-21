import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    // Localized labels for entity + action of an audit event.
    readonly property var entityLabels: ({
        "task": qsTr("Task"), "job": qsTr("Job"), "withdrawal": qsTr("Withdrawal"),
        "bonus": qsTr("Bonus"), "child": qsTr("Assignee")
    })
    readonly property var actionMeta: ({
        "created":         { label: qsTr("created"),           c: Theme.info },
        "updated":         { label: qsTr("edited"),            c: Theme.info },
        "deleted":         { label: qsTr("deleted"),           c: Theme.danger },
        "started":         { label: qsTr("started"),           c: Theme.success },
        "paused":          { label: qsTr("paused"),            c: Theme.warning },
        "stopped":         { label: qsTr("stopped"),           c: Theme.warning },
        "archived":        { label: qsTr("archived"),          c: Theme.textSecondary },
        "submitted":       { label: qsTr("sent for review"),   c: Theme.accent },
        "approved":        { label: qsTr("approved"),          c: Theme.success },
        "completed":       { label: qsTr("completed"),         c: Theme.success },
        "rejected":        { label: qsTr("rejected"),          c: Theme.danger },
        "rework":          { label: qsTr("sent for rework"),   c: Theme.warning },
        "declined":        { label: qsTr("declined"),          c: Theme.danger },
        "requested":       { label: qsTr("requested"),         c: Theme.warning },
        "paid":            { label: qsTr("paid out"),          c: Theme.accent },
        "confirmed":       { label: qsTr("receipt confirmed"), c: Theme.success },
        "overdue":         { label: qsTr("overdue"),           c: Theme.danger },
        "payment_changed": { label: qsTr("payment updated"),   c: Theme.success },
        "granted":         { label: qsTr("granted"),           c: Theme.success },
        "assigned":        { label: qsTr("assigned"),          c: Theme.info },
        "unassigned":      { label: qsTr("unassigned"),        c: Theme.textSecondary },
        "blocked":         { label: qsTr("blocked"),           c: Theme.danger },
        "unblocked":       { label: qsTr("unblocked"),         c: Theme.success },
        "status_changed":  { label: qsTr("status changed"),    c: Theme.info }
    })

    function applyFilters() {
        backend.setJournalFilter(
            entityFilter.model[entityFilter.currentIndex].value,
            childFilter.currentIndex > 0 && childFilter.currentIndex <= backend.childOptions.length
                ? backend.childOptions[childFilter.currentIndex - 1].id : "",
            periodFilter.model[periodFilter.currentIndex].value,
            searchField.text)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        ColumnLayout {
            spacing: 2
            Text {
                text: qsTr("Journal")
                font.pixelSize: Theme.fontSizeXl
                font.weight: Font.Bold
                color: Theme.textPrimary
            }
            Text {
                text: qsTr("Who did what and when — across the desktop, the phones and Telegram")
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
            }
        }

        // ------------------------------------------------ needs attention
        Card {
            visible: attentionList.count > 0
            Layout.fillWidth: true
            implicitHeight: attentionCol.implicitHeight + Theme.spacingMd * 2

            ColumnLayout {
                id: attentionCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingMd
                spacing: Theme.spacingSm

                Text {
                    text: qsTr("Needs attention")
                    font.pixelSize: Theme.fontSizeMd
                    font.weight: Font.Bold
                    color: Theme.warning
                }

                Repeater {
                    id: attentionList
                    model: backend.attentionModel
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd
                        Avatar { name: model.childName; color: model.childColor; size: 32; source: model.childAvatarUrl }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: qsTr("Withdrawal %1").arg(model.amountText)
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: Font.DemiBold
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: model.childName + " · " + model.requestedAtText
                                font.pixelSize: Theme.fontSizeXs
                                color: Theme.textSecondary
                            }
                        }
                        AppButton {
                            visible: model.status === "requested"
                            small: true
                            text: qsTr("Approve")
                            onClicked: backend.withdrawalApprove(model.wId)
                        }
                        AppButton {
                            visible: model.status === "requested"
                            small: true
                            variant: "danger"
                            text: qsTr("Decline")
                            onClicked: noteRef.openWith(
                                qsTr("Decline withdrawal"),
                                qsTr("Reason (the assignee will see it)"),
                                qsTr("Decline"),
                                function(reason) { backend.withdrawalReject(model.wId, reason) },
                                true)
                        }
                        AppButton {
                            visible: model.status === "approved"
                            small: true
                            text: qsTr("Pay…")
                            onClicked: withdrawalPayRef.openFor(model.wId, model.childName, model.amountText)
                        }
                    }
                }
            }
        }

        // ------------------------------------------------ filters
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            AppComboBox {
                id: entityFilter
                Layout.preferredWidth: 150
                textRole: "label"
                model: [
                    { label: qsTr("All events"), value: "" },
                    { label: qsTr("Tasks"), value: "task" },
                    { label: qsTr("Jobs"), value: "job" },
                    { label: qsTr("Withdrawals"), value: "withdrawal" },
                    { label: qsTr("Bonuses"), value: "bonus" },
                    { label: qsTr("Assignees"), value: "child" }
                ]
                onActivated: root.applyFilters()
            }
            AppComboBox {
                id: childFilter
                Layout.preferredWidth: 150
                textRole: "name"
                model: [{ name: qsTr("Everyone"), id: "" }].concat(backend.childOptions)
                onActivated: root.applyFilters()
            }
            AppComboBox {
                id: periodFilter
                Layout.preferredWidth: 130
                textRole: "label"
                model: [
                    { label: qsTr("All time"), value: "" },
                    { label: qsTr("Today"), value: "today" },
                    { label: qsTr("7 days"), value: "7d" },
                    { label: qsTr("30 days"), value: "30d" }
                ]
                onActivated: root.applyFilters()
            }
            AppTextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: qsTr("Search: task, assignee, note…")
                onTextEdited: searchDebounce.restart()
                Timer { id: searchDebounce; interval: 250; onTriggered: root.applyFilters() }
            }
        }

        // ------------------------------------------------ audit feed
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.spacingSm
            model: backend.journalModel

            section.property: "dateText"
            section.criteria: ViewSection.FullString
            section.delegate: Text {
                required property string section
                text: section
                topPadding: Theme.spacingSm
                bottomPadding: 2
                font.pixelSize: Theme.fontSizeXs
                font.weight: Font.Bold
                color: Theme.textSecondary
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: qsTr("No events match the filters")
                font.pixelSize: Theme.fontSizeMd
                color: Theme.textSecondary
            }

            delegate: Card {
                id: entryCard
                width: list.width
                implicitHeight: row.implicitHeight + Theme.spacingMd * 2
                shadow: false
                readonly property var meta: root.actionMeta[model.action] || { label: model.action, c: Theme.textSecondary }
                color: hoverArea.containsMouse ? Theme.surfaceAlt : Theme.surface
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                // Any entry opens the full story of the entity it belongs to.
                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: backend.openTimeline(model.entity, model.refId, model.childName)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    width: 4
                    radius: 2
                    color: entryCard.meta.c
                }

                RowLayout {
                    id: row
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.spacingLg
                    anchors.rightMargin: Theme.spacingMd
                    spacing: Theme.spacingMd

                    Avatar {
                        name: model.actorKind === "system" ? "⚙" : (model.actorName || model.childName)
                        color: model.actorKind === "child" ? model.childColor : Theme.accentSoft
                        size: 34
                        source: model.actorKind === "child" ? model.childAvatarUrl : ""
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: Theme.spacingSm
                            Text {
                                text: model.actorKind === "system"
                                    ? qsTr("System") : (model.actorName || model.childName || "—")
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: Font.DemiBold
                                color: Theme.textPrimary
                            }
                            Chip {
                                text: (root.entityLabels[model.entity] || model.entity) + " · " + entryCard.meta.label
                                chipColor: entryCard.meta.c
                            }
                        }
                        Text {
                            text: model.entityTitle
                                + (model.childName && model.entity !== "child" ? " — " + model.childName : "")
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: model.noteText.length > 0
                            text: model.noteText
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            visible: model.amountText.length > 0
                            text: model.amountText
                            font.pixelSize: Theme.fontSizeMd
                            font.weight: Font.Bold
                            color: entryCard.meta.c
                            Layout.alignment: Qt.AlignRight
                        }
                        Text {
                            text: model.timeText
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textSecondary
                            Layout.alignment: Qt.AlignRight
                        }
                    }

                    // A granted bonus stays manageable right from its journal entry.
                    AppButton {
                        visible: model.entity === "bonus" && model.bonusAlive && model.action === "granted"
                        small: true
                        variant: "secondary"
                        text: qsTr("Edit")
                        onClicked: bonusDialogRef.openForEdit(model.refId, model.bonusAmount, model.bonusNote)
                    }
                    AppButton {
                        visible: model.entity === "bonus" && model.bonusAlive && model.action === "granted"
                        small: true
                        variant: "ghost"
                        text: qsTr("Delete")
                        onClicked: confirmRef.openWith(
                            qsTr("Delete bonus"),
                            qsTr("The bonus of %1 will be removed from the assignee's balance. Delete?").arg(model.amountText),
                            function() { backend.deleteBonus(model.refId) },
                            true)
                    }

                    Text {
                        visible: model.isTask
                        text: "›"
                        font.pixelSize: Theme.fontSizeXl
                        color: Theme.textSecondary
                    }
                }
            }
        }
    }
}
