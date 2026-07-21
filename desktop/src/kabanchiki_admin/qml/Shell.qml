import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent
    property int currentTab: 0 // 0 tasks, 1 jobs, 2 balances, 3 withdrawals, 4 journal, 5 settings
    property string selectedChildId: ""

    Rectangle { anchors.fill: parent; color: Theme.bg }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ------------------------------------------------ sidebar
        Rectangle {
            Layout.preferredWidth: 420
            Layout.fillHeight: true
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingMd
                spacing: Theme.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    Image {
                        source: backend.appIconUrl
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }
                    Text {
                        text: "Kabanchiki"
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Font.Bold
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: backend.connected ? Theme.success : Theme.danger
                        Behavior on color { ColorAnimation { duration: Theme.animMed } }
                    }
                }

                AppButton {
                    text: qsTr("+ Add assignee")
                    variant: "secondary"
                    Layout.fillWidth: true
                    onClicked: childDialog.openForCreate()
                }

                Text {
                    text: qsTr("Assignees")
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    color: Theme.textSecondary
                }

                ListView {
                    id: childList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.spacingXs
                    model: backend.childrenModel
                    delegate: Rectangle {
                        width: childList.width
                        height: 66
                        radius: Theme.radiusSm
                        readonly property bool selected: root.selectedChildId === model.childId
                        color: selected ? Qt.alpha(Theme.accent, 0.10)
                             : (mouse.containsMouse ? Theme.surfaceAlt : Qt.alpha(Theme.surfaceAlt, 0))
                        border.width: selected ? 1 : 0
                        border.color: Qt.alpha(Theme.accent, 0.35)
                        Behavior on color { ColorAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSm
                            spacing: Theme.spacingSm
                            opacity: model.blocked ? 0.5 : 1.0

                            Avatar { name: model.displayName; color: model.color; size: 36; source: model.avatarUrl }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        text: model.displayName
                                        font.pixelSize: Theme.fontSizeMd
                                        font.weight: Font.DemiBold
                                        color: Theme.textPrimary
                                        elide: Text.ElideRight
                                    }
                                    PresenceBadge {
                                        visible: !model.blocked
                                        presence: model.presence
                                    }
                                    Chip {
                                        visible: model.blocked
                                        text: qsTr("blocked")
                                        chipColor: Theme.danger
                                        filled: true
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                                Text {
                                    text: model.currentTask.length > 0
                                        ? qsTr("▶ %1").arg(model.currentTask)
                                        : qsTr("%1 active · balance %2").arg(model.activeCount).arg(model.balanceText)
                                    font.pixelSize: Theme.fontSizeXs
                                    color: model.currentTask.length > 0 ? Theme.success : Theme.textSecondary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        // Kebab menu button, appears on hover.
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 6
                            width: 26; height: 26; radius: 13
                            visible: mouse.containsMouse || menuBtn.containsMouse
                            color: menuBtn.containsMouse ? Theme.surfacePressed : Theme.surfaceAlt
                            Text { anchors.centerIn: parent; text: "⋯"; font.pixelSize: 16; color: Theme.textSecondary }
                            MouseArea {
                                id: menuBtn
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    childMenu.setChild(model)
                                    childMenu.popup(menuBtn, 0, height)
                                }
                            }
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            z: -1
                            onClicked: function(event) {
                                if (event.button === Qt.RightButton) {
                                    childMenu.setChild(model)
                                    childMenu.popup()
                                } else {
                                    // Click selects the assignee and filters the task list.
                                    root.selectedChildId = root.selectedChildId === model.childId ? "" : model.childId
                                    root.currentTab = 0
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs

                    NavButton {
                        text: qsTr("Tasks")
                        active: root.currentTab === 0
                        badge: backend.reviewCount
                        onClicked: root.currentTab = 0
                    }
                    NavButton {
                        text: qsTr("Hourly jobs")
                        active: root.currentTab === 1
                        onClicked: root.currentTab = 1
                    }
                    NavButton { text: qsTr("Balances"); active: root.currentTab === 2; onClicked: root.currentTab = 2 }
                    NavButton {
                        text: qsTr("Withdrawals")
                        active: root.currentTab === 3
                        badge: backend.pendingCount
                        onClicked: root.currentTab = 3
                    }
                    NavButton { text: qsTr("Journal"); active: root.currentTab === 4; onClicked: root.currentTab = 4 }
                    NavButton { text: qsTr("Settings"); active: root.currentTab === 5; onClicked: root.currentTab = 5 }
                }
            }
        }

        // ------------------------------------------------ content
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTab

            TasksPage {
                childFilter: root.selectedChildId
                onChildFilterRequested: function(childId) { root.selectedChildId = childId }
            }
            JobsPage { }
            BalancesPage { }
            WithdrawalsPage { }
            JournalPage { }
            SettingsPage { }
        }
    }

    AppMenu {
        id: childMenu
        property string childId: ""
        property string childName: ""
        property string childColor: "#CDB1B1"
        property bool childBlocked: false
        property string childAvatarUrl: ""

        function setChild(m) {
            childId = m.childId
            childName = m.displayName
            childColor = m.color
            childBlocked = m.blocked
            childAvatarUrl = m.avatarUrl
        }

        AppMenuItem {
            text: qsTr("Show tasks")
            onTriggered: {
                root.selectedChildId = childMenu.childId
                root.currentTab = 0
            }
        }
        AppMenuItem {
            text: qsTr("Adjust balance…")
            onTriggered: adjustBalanceDialog.openFor(childMenu.childId, childMenu.childName)
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: qsTr("Edit…")
            onTriggered: childEditDialog.openFor(
                childMenu.childId, childMenu.childName, childMenu.childColor, childMenu.childAvatarUrl)
        }
        AppMenuItem {
            text: qsTr("Change password…")
            onTriggered: passwordDialog.openFor(childMenu.childId, childMenu.childName)
        }
        AppMenuItem {
            text: childMenu.childBlocked ? qsTr("Unblock") : qsTr("Block")
            onTriggered: {
                if (childMenu.childBlocked) {
                    backend.setChildBlocked(childMenu.childId, false)
                } else {
                    confirmDialog.openWith(
                        qsTr("Block assignee"),
                        qsTr("“%1” will not be able to sign in or do tasks until you unblock them. Continue?").arg(childMenu.childName),
                        function() { backend.setChildBlocked(childMenu.childId, true) },
                        false)
                }
            }
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: qsTr("Delete…")
            danger: true
            onTriggered: confirmDialog.openWith(
                qsTr("Delete assignee"),
                qsTr("“%1” and all their tasks, jobs and history will be permanently deleted. This cannot be undone.").arg(childMenu.childName),
                function() { backend.deleteChild(childMenu.childId) },
                true)
        }
    }

    ChildDialog { id: childDialog }
    ChildEditDialog { id: childEditDialog }
    BonusDialog { id: bonusDialog }
    AdjustBalanceDialog { id: adjustBalanceDialog }
    WithdrawalPayDialog { id: withdrawalPayDialog }
    PayoutDialog { id: payoutDialog }
    PasswordDialog { id: passwordDialog }
    TaskDialog { id: taskDialog }
    JobDialog { id: jobDialog }
    TaskDetailDialog { id: taskDetailDialog }
    ConfirmDialog { id: confirmDialog }
    NoteDialog { id: noteDialog }
    Lightbox { id: lightbox }
    TimelineDialog { id: timelineDialog }

    // The backend answers openTimeline() here, so any page can ask for a story
    // without owning the dialog itself.
    Connections {
        target: backend
        function onTimelineReady(steps, entity, subtitle) {
            timelineDialog.steps = steps
            timelineDialog.entity = entity
            timelineDialog.subtitle = subtitle
            timelineDialog.open()
        }
    }

    // Pages reach dialogs through these:
    property alias taskDialogRef: taskDialog
    property alias jobDialogRef: jobDialog
    property alias taskDetailRef: taskDetailDialog
    property alias confirmRef: confirmDialog
    property alias bonusDialogRef: bonusDialog
    property alias balanceAdjustRef: adjustBalanceDialog
    property alias withdrawalPayRef: withdrawalPayDialog
    property alias payoutRef: payoutDialog
    property alias noteRef: noteDialog
    property alias lightboxRef: lightbox
}
