import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The full story of a single entity: every logged step, oldest first, as a
// vertical timeline. Opened from the journal, the payout registry and the
// balance ledger, so any one task or transaction can be followed on its own.
AppDialog {
    id: root

    property var steps: []
    property string entity: ""
    property string subtitle: ""

    title: qsTr("History")

    // Same vocabulary as the journal, so a step reads identically in both.
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
    readonly property var entityLabels: ({
        "task": qsTr("Task"), "job": qsTr("Job"), "withdrawal": qsTr("Withdrawal"),
        "bonus": qsTr("Bonus"), "child": qsTr("Assignee")
    })

    function meta(action) {
        return actionMeta[action] || { label: action, c: Theme.textSecondary }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingMd

        // A ColumnLayout recomputes implicitWidth from its children, so an
        // explicit one is ignored; this zero-height strut sets the dialog width.
        Item { implicitWidth: 520; implicitHeight: 0 }

        Text {
            visible: root.subtitle.length > 0
            text: (root.entityLabels[root.entity] || root.entity) + " · " + root.subtitle
            font.pixelSize: Theme.fontSizeMd
            font.weight: Font.DemiBold
            color: Theme.textPrimary
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Text {
            visible: root.steps.length === 0
            text: qsTr("No events yet")
            font.pixelSize: Theme.fontSizeSm
            color: Theme.textSecondary
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            Layout.topMargin: Theme.spacingLg
            Layout.bottomMargin: Theme.spacingLg
        }

        // Scrolls on its own when a story gets long; the dialog stays put.
        Flickable {
            id: stepsFlick
            visible: root.steps.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(stepsCol.implicitHeight, 420)
            contentHeight: stepsCol.implicitHeight
            contentWidth: width
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { id: stepsBar; policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: stepsCol
                // Bind to the Flickable itself: a direct child's `parent` is the
                // content item, whose width is not the visible width.
                width: stepsFlick.width - (stepsBar.visible ? stepsBar.width : 0)
                spacing: 0

                Repeater {
                    model: root.steps
                    delegate: RowLayout {
                        id: stepRow
                        required property var modelData
                        required property int index
                        readonly property var m: root.meta(modelData.action)
                        readonly property bool last: index === root.steps.length - 1
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd

                        // Dot + connecting spine.
                        Item {
                            Layout.preferredWidth: 12
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignTop
                            implicitHeight: rowBody.implicitHeight
                            Rectangle {
                                width: 2
                                color: Theme.border
                                x: 5
                                y: 12
                                height: stepRow.last ? 0 : parent.height - 6
                                visible: !stepRow.last
                            }
                            Rectangle {
                                width: 10; height: 10; radius: 5
                                y: 6
                                color: stepRow.m.c
                            }
                        }

                        ColumnLayout {
                            id: rowBody
                            Layout.fillWidth: true
                            Layout.bottomMargin: stepRow.last ? 0 : Theme.spacingMd
                            spacing: 1

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSm
                                Text {
                                    text: stepRow.m.label
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.DemiBold
                                    color: Theme.textPrimary
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: stepRow.modelData.timeText
                                    font.pixelSize: Theme.fontSizeXs
                                    color: Theme.textSecondary
                                }
                            }
                            Text {
                                readonly property string d: stepRow.modelData.detailText || ""
                                visible: d.length > 0
                                text: d
                                font.pixelSize: Theme.fontSizeSm
                                color: Theme.textSecondary
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Close"); onClicked: root.close() }
        }
    }
}
