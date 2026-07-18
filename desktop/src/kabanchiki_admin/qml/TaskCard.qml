import QtQuick
import QtQuick.Layouts

Card {
    id: root
    signal clicked()

    implicitHeight: contentRow.implicitHeight + Theme.spacingMd * 2
    shadow: false

    readonly property var statusInfo: {
        switch (model.status) {
        case "new": return { label: model.declineReason.length > 0 ? qsTr("Rework") : qsTr("New"),
                             color: model.declineReason.length > 0 ? Theme.warning : Theme.info }
        case "in_progress": return { label: qsTr("In progress"), color: Theme.accent }
        case "paused": return { label: qsTr("Paused"), color: Theme.warning }
        case "submitted": return { label: qsTr("Under review"), color: Theme.info }
        case "done": return { label: qsTr("Done"), color: Theme.success }
        case "declined": return { label: qsTr("Declined"), color: Theme.danger }
        default: return { label: model.status, color: Theme.textSecondary }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 8
        width: 4
        radius: 2
        color: model.diffColor
    }

    RowLayout {
        id: contentRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spacingLg
        anchors.rightMargin: Theme.spacingMd
        spacing: Theme.spacingMd

        Avatar { name: model.childName; color: model.childColor; size: 36; source: model.childAvatarUrl }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: model.title
                font.pixelSize: Theme.fontSizeMd
                font.weight: Font.DemiBold
                color: Theme.textPrimary
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: model.childName + " · " + model.createdAtText
                    + (model.createdBy.length > 0 ? qsTr(" · by %1").arg(model.createdBy) : "")
                font.pixelSize: Theme.fontSizeXs
                color: Theme.textSecondary
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        // Deadline badge (compact) — hidden for finished tasks.
        Chip {
            visible: model.deadlineState !== "none"
                && model.status !== "done" && model.status !== "declined"
            text: "⏰ " + model.deadlineText
            chipColor: model.deadlineState === "overdue" ? Theme.danger
                : (model.deadlineState === "soon" ? Theme.warning : Theme.textSecondary)
            filled: model.deadlineState === "overdue"
        }

        DifficultyBadge { level: model.difficulty; showLabel: false }
        Chip { text: model.rewardText; chipColor: Theme.accentDark }
        Chip { text: root.statusInfo.label; chipColor: root.statusInfo.color }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }

    color: mouse.containsMouse ? Theme.surfaceAlt : Theme.surface
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    scale: mouse.pressed ? 0.99 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
}
