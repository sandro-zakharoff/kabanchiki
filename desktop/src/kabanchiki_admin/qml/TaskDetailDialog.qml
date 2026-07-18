import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppDialog {
    id: root
    width: 580

    property var task: null

    readonly property var statusMeta: ({
        "new":        { label: qsTr("New"),          c: Theme.info },
        "in_progress":{ label: qsTr("In progress"),  c: Theme.success },
        "paused":     { label: qsTr("Paused"),       c: Theme.warning },
        "submitted":  { label: qsTr("In review"),    c: Theme.accent },
        "done":       { label: qsTr("Done"),         c: Theme.success },
        "declined":   { label: qsTr("Declined"),     c: Theme.danger }
    })

    function openFor(model) {
        task = {
            taskId: model.taskId, title: model.title, childName: model.childName,
            childColor: model.childColor, description: model.description, photoUrl: model.photoUrl,
            rewardText: model.rewardText, rewardType: model.rewardType, rewardAmount: model.rewardAmount,
            proofText: model.proofText, proofPhoto: model.proofPhoto, difficulty: model.difficulty,
            diffColor: model.diffColor, requirements: model.requirements, status: model.status,
            proofTextContent: model.proofTextContent, proofPhotoUrl: model.proofPhotoUrl,
            totalText: model.totalText, earnedText: model.earnedText, createdAtText: model.createdAtText,
            completedAtText: model.completedAtText, declineReason: model.declineReason,
            completionMode: model.completionMode, createdBy: model.createdBy,
            deadlineText: model.deadlineText, deadlineState: model.deadlineState,
            deadlineIso: model.deadlineIso,
            photosVar: model.photosVar || [], proofsVar: model.proofsVar || []
        }
        title = model.title
        subtitle = model.childName
        open()
    }

    // Full-size gallery for the lightbox.
    function galleryUrls(items) {
        var urls = []
        for (var i = 0; i < items.length; i++) urls.push(items[i].url)
        return urls
    }

    // Keep the open dialog in sync with the model: when a refresh lands
    // (realtime, another device, our own mutation confirmed), re-read the row
    // so status/proof never go stale without reopening.
    Connections {
        target: backend.tasksModel
        enabled: root.visible && root.task !== null
        function onModelReset() {
            var rows = backend.tasksModel.all()
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].taskId === root.task.taskId) {
                    root.task = rows[i]
                    root.title = rows[i].title
                    root.subtitle = rows[i].childName
                    return
                }
            }
            root.close()   // the task was deleted elsewhere
        }
    }

    contentItem: Flickable {
        implicitHeight: Math.min(col.implicitHeight, root.maxContentHeight)
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: col
            width: parent.width
            spacing: Theme.spacingMd

            // Chips: status, difficulty, reward, no-timer.
            Flow {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Chip {
                    text: root.task ? root.statusMeta[root.task.status].label : ""
                    chipColor: root.task ? root.statusMeta[root.task.status].c : Theme.accent
                    filled: true
                }
                DifficultyBadge { level: root.task ? root.task.difficulty : 1 }
                Chip { text: root.task ? root.task.rewardText : ""; chipColor: Theme.accentDark }
                Chip {
                    visible: root.task && root.task.completionMode === "simple"
                    text: qsTr("no timer"); chipColor: Theme.info
                }
                Chip {
                    visible: root.task && root.task.deadlineState !== undefined
                        && root.task.deadlineState !== "none"
                    text: "⏰ " + (root.task ? root.task.deadlineText : "")
                    chipColor: root.task && root.task.deadlineState === "overdue" ? Theme.danger
                        : (root.task && root.task.deadlineState === "soon" ? Theme.warning : Theme.textSecondary)
                    filled: root.task && root.task.deadlineState === "overdue"
                }
            }

            // Accepted tasks credit the reward to the assignee's balance.
            Rectangle {
                visible: root.task && root.task.status === "done"
                Layout.fillWidth: true
                implicitHeight: paidRow.implicitHeight + Theme.spacingMd
                radius: Theme.radiusSm
                color: Qt.alpha(Theme.success, 0.10)
                RowLayout {
                    id: paidRow
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    spacing: Theme.spacingSm
                    Text { text: "✓"; font.pixelSize: Theme.fontSizeLg; color: Theme.success }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Credited to the balance: %1").arg(root.task ? root.task.earnedText : "")
                        font.pixelSize: Theme.fontSizeMd; font.weight: Font.DemiBold
                        color: Theme.textPrimary
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Description.
            Text {
                visible: root.task && root.task.description.length > 0
                text: root.task ? root.task.description : ""
                font.pixelSize: Theme.fontSizeMd
                color: Theme.textPrimary
                lineHeight: 1.25
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // Task photos (from the parent) — a gallery of thumbnails.
            ColumnLayout {
                visible: root.task && (root.task.photosVar || []).length > 0
                Layout.fillWidth: true
                spacing: Theme.spacingXs
                Text {
                    text: qsTr("Task photos")
                    font.pixelSize: Theme.fontSizeXs; font.weight: Font.DemiBold
                    color: Theme.textSecondary
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    Repeater {
                        model: root.task ? (root.task.photosVar || []) : []
                        delegate: ImageThumb {
                            required property var modelData
                            required property int index
                            width: 116; height: 116
                            source: modelData.thumbUrl
                            onActivated: lightboxRef.showList(root.galleryUrls(root.task.photosVar), index)
                        }
                    }
                }
            }

            // Requirements.
            Rectangle {
                visible: root.task && root.task.requirements.length > 0
                Layout.fillWidth: true
                implicitHeight: reqCol.implicitHeight + Theme.spacingMd * 2
                radius: Theme.radiusSm
                color: Qt.alpha(Theme.warning, 0.08)
                border.width: 1
                border.color: Qt.alpha(Theme.warning, 0.30)
                ColumnLayout {
                    id: reqCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.margins: Theme.spacingMd
                    spacing: 3
                    Text {
                        text: qsTr("Requirements")
                        font.pixelSize: Theme.fontSizeXs; font.weight: Font.Bold; color: Theme.warning
                    }
                    Text {
                        text: root.task ? root.task.requirements : ""
                        font.pixelSize: Theme.fontSizeMd; color: Theme.textPrimary
                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
            }

            // Meta rows.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: root.task ? [
                        { l: qsTr("Created"),   v: root.task.createdAtText,   show: true,  accent: false },
                        { l: qsTr("Created by"), v: root.task.createdBy || "", show: (root.task.createdBy || "").length > 0, accent: false },
                        { l: qsTr("Finished"),  v: root.task.completedAtText, show: root.task.completedAtText.length > 0, accent: false },
                        { l: qsTr("Time spent"),v: root.task.totalText,       show: root.task.totalText !== "0:00:00",   accent: false },
                        { l: qsTr("Earned"),    v: root.task.earnedText,      show: root.task.earnedText.length > 0,     accent: true }
                    ] : []
                    delegate: RowLayout {
                        required property var modelData
                        visible: modelData.show
                        Layout.fillWidth: true
                        Layout.preferredHeight: modelData.show ? 30 : 0
                        Text {
                            text: modelData.l
                            font.pixelSize: Theme.fontSizeSm; color: Theme.textSecondary
                            Layout.preferredWidth: 120
                        }
                        Text {
                            text: modelData.v
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: modelData.accent ? Font.Bold : Font.Normal
                            color: modelData.accent ? Theme.accent : Theme.textPrimary
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // Proof from the assignee.
            Rectangle {
                visible: root.task && (root.task.proofTextContent.length > 0
                    || (root.task.proofsVar || []).length > 0)
                Layout.fillWidth: true
                implicitHeight: proofCol.implicitHeight + Theme.spacingMd * 2
                radius: Theme.radiusSm
                color: Qt.alpha(Theme.success, 0.08)
                border.width: 1
                border.color: Qt.alpha(Theme.success, 0.30)
                ColumnLayout {
                    id: proofCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.margins: Theme.spacingMd
                    spacing: Theme.spacingSm
                    Text {
                        text: qsTr("Proof from the assignee")
                        font.pixelSize: Theme.fontSizeXs; font.weight: Font.Bold; color: Theme.success
                    }
                    Text {
                        visible: root.task && root.task.proofTextContent.length > 0
                        text: root.task ? root.task.proofTextContent : ""
                        font.pixelSize: Theme.fontSizeMd; color: Theme.textPrimary
                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Flow {
                        visible: root.task && (root.task.proofsVar || []).length > 0
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        Repeater {
                            model: root.task ? (root.task.proofsVar || []) : []
                            delegate: ImageThumb {
                                required property var modelData
                                required property int index
                                width: 116; height: 116
                                source: modelData.thumbUrl
                                onActivated: lightboxRef.showList(root.galleryUrls(root.task.proofsVar), index)
                            }
                        }
                    }
                }
            }

            // Decline / rework note.
            Rectangle {
                visible: root.task && root.task.declineReason.length > 0
                Layout.fillWidth: true
                implicitHeight: reasonText.implicitHeight + Theme.spacingMd * 2
                radius: Theme.radiusSm
                readonly property bool isRework: root.task && root.task.status === "new"
                color: Qt.alpha(isRework ? Theme.warning : Theme.danger, 0.09)
                border.width: 1
                border.color: Qt.alpha(isRework ? Theme.warning : Theme.danger, 0.30)
                Text {
                    id: reasonText
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter; anchors.margins: Theme.spacingMd
                    text: (parent.isRework ? qsTr("Sent for rework: %1") : qsTr("Decline reason: %1"))
                          .arg(root.task ? root.task.declineReason : "")
                    font.pixelSize: Theme.fontSizeMd
                    color: parent.isRework ? Qt.darker(Theme.warning, 1.1) : Theme.danger
                    wrapMode: Text.WordWrap
                }
            }

        }
    }

    // Actions footer — always visible, adapts to the task status.
    footer: Rectangle {
        implicitHeight: 68
        color: "transparent"
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 24; anchors.rightMargin: 24
            spacing: Theme.spacingSm

            // Review actions for a submitted task.
            AppButton {
                visible: root.task && root.task.status === "submitted"
                text: qsTr("Reject"); variant: "danger"
                onClicked: {
                    var id = root.task.taskId; root.close()
                    noteRef.openWith(qsTr("Reject the task"), qsTr("Reason (the assignee will see it)"),
                        qsTr("Reject"), function(note) { backend.reviewTask(id, "reject", note) }, true)
                }
            }
            AppButton {
                visible: root.task && root.task.status === "submitted"
                text: qsTr("Send for rework"); variant: "secondary"
                onClicked: {
                    var id = root.task.taskId; root.close()
                    noteRef.openWith(qsTr("Send for rework"), qsTr("What to fix (the assignee will see it)"),
                        qsTr("Send"), function(note) { backend.reviewTask(id, "rework", note) }, false)
                }
            }

            // Non-review actions.
            AppButton {
                visible: root.task && root.task.status !== "submitted"
                text: qsTr("Delete"); variant: "ghost"
                onClicked: {
                    var id = root.task.taskId; root.close()
                    confirmRef.openWith(qsTr("Delete task"),
                        qsTr("The task will disappear from the assignee's phone as well. Delete?"),
                        function() { backend.deleteTask(id) }, true)
                }
            }

            Item { Layout.fillWidth: true }

            AppButton {
                visible: root.task && root.task.status === "new"
                text: qsTr("Edit"); variant: "secondary"
                onClicked: { var t = root.task; root.close(); taskDialogRef.openForEdit(t) }
            }
            AppButton {
                visible: root.task && (root.task.status === "done" || root.task.status === "declined")
                text: qsTr("Re-issue"); variant: "secondary"
                onClicked: { var id = root.task.taskId; root.close(); backend.duplicateTask(id) }
            }
            AppButton {
                visible: root.task && root.task.status === "submitted"
                text: qsTr("Accept")
                // Stay open: optimistically flip to 'done' so the "credited to
                // balance" note appears in place; the live model sync confirms.
                // Accepting credits the reward to the assignee's balance.
                onClicked: {
                    var t = root.task; t.status = "done"; root.task = t
                    backend.reviewTask(t.taskId, "approve", "")
                }
            }
            AppButton {
                visible: root.task && root.task.status !== "submitted"
                text: qsTr("Close"); variant: "secondary"
                onClicked: root.close()
            }
        }
    }
}
