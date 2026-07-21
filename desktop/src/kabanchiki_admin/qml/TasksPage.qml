import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    property string statusFilter: "all"
    property string childFilter: ""
    property string authorFilter: ""
    signal childFilterRequested(string childId)

    LocationDialog { id: locationDialog }

    // Reactive combo model: rebuilt whenever the assignee list changes.
    readonly property var childOptions: {
        var options = [{ name: qsTr("All assignees"), id: "" }]
        var rows = backend.childOptions
        for (var i = 0; i < rows.length; i++)
            options.push({ name: rows[i].name, id: rows[i].id })
        return options
    }

    onChildFilterChanged: {
        for (var i = 0; i < childOptions.length; i++)
            if (childOptions[i].id === childFilter) { childCombo.currentIndex = i; break }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: qsTr("Tasks")
                font.pixelSize: Theme.fontSizeXl
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            Item { Layout.fillWidth: true }

            AppComboBox {
                id: childCombo
                Layout.preferredWidth: 200
                textRole: "name"
                model: root.childOptions
                onActivated: root.childFilterRequested(model[currentIndex].id)
            }

            // Author filter appears once there is more than one owner.
            AppComboBox {
                id: authorCombo
                visible: backend.owners.length > 1
                Layout.preferredWidth: 170
                textRole: "name"
                model: {
                    var options = [{ name: qsTr("All authors"), id: "" }]
                    var owners = backend.owners
                    for (var i = 0; i < owners.length; i++)
                        options.push({ name: owners[i].display_name || owners[i].email, id: owners[i].id })
                    return options
                }
                onActivated: root.authorFilter = model[currentIndex].id
            }

            AppButton {
                text: qsTr("+ New task")
                onClicked: taskDialogRef.openForCreate()
            }
        }

        // Selected-assignee profile header (reactive via the model).
        Repeater {
            model: backend.childrenModel
            delegate: Card {
                visible: root.childFilter === model.childId
                Layout.fillWidth: true
                implicitHeight: visible ? headerRow.implicitHeight + Theme.spacingMd * 2 : 0
                shadow: false

                RowLayout {
                    id: headerRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.spacingMd
                    anchors.rightMargin: Theme.spacingMd
                    spacing: Theme.spacingMd

                    Avatar { name: model.displayName; color: model.color; size: 44; source: model.avatarUrl }

                    ColumnLayout {
                        spacing: 3
                        RowLayout {
                            spacing: 6
                            Text {
                                text: model.displayName
                                font.pixelSize: Theme.fontSizeLg
                                font.weight: Font.Bold
                                color: Theme.textPrimary
                            }
                            PresenceBadge { visible: !model.blocked; presence: model.presence }
                            Chip { visible: model.blocked; text: qsTr("blocked"); chipColor: Theme.danger; filled: true }
                        }
                        Text {
                            text: model.currentTask.length > 0 ? qsTr("▶ %1").arg(model.currentTask) : qsTr("no active task")
                            font.pixelSize: Theme.fontSizeXs
                            color: model.currentTask.length > 0 ? Theme.success : Theme.textSecondary
                        }
                        // Device: app version + last activity.
                        RowLayout {
                            spacing: 6
                            Chip {
                                visible: model.appVersion.length > 0
                                text: model.appVersion
                                chipColor: model.versionOutdated ? Theme.warning : Theme.textSecondary
                                filled: model.versionOutdated
                            }
                            Text {
                                visible: model.appVersion.length > 0 && model.versionOutdated
                                text: qsTr("update available")
                                font.pixelSize: Theme.fontSizeXs
                                color: Theme.warning
                            }
                            Text {
                                visible: model.appVersion.length === 0
                                text: qsTr("no device")
                                font.pixelSize: Theme.fontSizeXs
                                color: Theme.textSecondary
                            }
                            Text {
                                visible: model.lastSeenText.length > 0
                                text: qsTr("· last seen %1").arg(model.lastSeenText)
                                font.pixelSize: Theme.fontSizeXs
                                color: Theme.textSecondary
                            }
                        }
                        // Location: where the assignee's phone last reported from.
                        RowLayout {
                            spacing: 6
                            Text {
                                text: "📍"
                                font.pixelSize: Theme.fontSizeXs
                            }
                            Text {
                                text: model.hasLocation ? model.locationText : qsTr("no location data")
                                font.pixelSize: Theme.fontSizeXs
                                color: model.locationStale ? Theme.warning
                                    : (model.hasLocation ? Theme.textPrimary : Theme.textSecondary)
                            }
                            Text {
                                visible: model.locationStale
                                text: qsTr("· not updating")
                                font.pixelSize: Theme.fontSizeXs
                                color: Theme.warning
                            }
                            Text {
                                visible: model.hasLocation
                                text: qsTr("open map")
                                font.pixelSize: Theme.fontSizeXs
                                font.underline: mapLink.containsMouse
                                color: Theme.accent
                                MouseArea {
                                    id: mapLink
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: locationDialog.openFor(model.childId, model.displayName)
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Inline stat blocks.
                    ColumnLayout {
                        spacing: 0
                        Text { text: model.activeCount + " / " + model.doneCount; font.pixelSize: Theme.fontSizeMd; font.weight: Font.Bold; color: Theme.textPrimary; Layout.alignment: Qt.AlignHCenter }
                        Text { text: qsTr("active / done"); font.pixelSize: Theme.fontSizeXs; color: Theme.textSecondary; Layout.alignment: Qt.AlignHCenter }
                    }
                    Rectangle { width: 1; Layout.preferredHeight: 32; color: Theme.border }
                    ColumnLayout {
                        spacing: 0
                        AcornAmount { text: model.balanceText; fontSize: Theme.fontSizeLg; fontWeight: Font.Bold; color: Theme.accent; Layout.alignment: Qt.AlignHCenter }
                        Text { text: qsTr("balance"); font.pixelSize: Theme.fontSizeXs; color: Theme.textSecondary; Layout.alignment: Qt.AlignHCenter }
                    }

                    AppButton {
                        small: true
                        variant: "secondary"
                        text: qsTr("Adjust")
                        onClicked: balanceAdjustRef.openFor(model.childId, model.displayName)
                    }
                }
            }
        }

        RowLayout {
            spacing: Theme.spacingSm
            Repeater {
                model: [
                    { key: "all", label: qsTr("All") },
                    { key: "new", label: qsTr("New") },
                    { key: "in_progress", label: qsTr("In progress") },
                    { key: "submitted", label: qsTr("Under review") },
                    { key: "done", label: qsTr("Done") },
                    { key: "declined", label: qsTr("Declined") }
                ]
                delegate: Rectangle {
                    required property var modelData
                    height: 30
                    width: chipLabel.implicitWidth + 26
                    radius: 15
                    color: root.statusFilter === modelData.key ? Theme.accent : Theme.surface
                    border.width: 1
                    border.color: root.statusFilter === modelData.key ? Theme.accent : Theme.border
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Font.DemiBold
                        color: root.statusFilter === modelData.key ? "#FFFFFF" : Theme.textPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.statusFilter = modelData.key
                    }
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.spacingSm
            model: backend.tasksModel

            ColumnLayout {
                anchors.centerIn: parent
                visible: list.count === 0
                spacing: Theme.spacingSm
                Text {
                    text: "📋"
                    font.pixelSize: 40
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: qsTr("No tasks yet")
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: qsTr("Create the first task with the button above")
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textSecondary
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            section.property: "dateSection"
            section.delegate: Text {
                required property string section
                text: section
                topPadding: Theme.spacingMd
                bottomPadding: Theme.spacingXs
                font.pixelSize: Theme.fontSizeSm
                font.weight: Font.DemiBold
                color: Theme.textSecondary
            }

            delegate: TaskCard {
                width: list.width
                visible: (root.statusFilter === "all" || model.status === root.statusFilter)
                    && (root.childFilter === "" || model.childId === root.childFilter)
                    && (root.authorFilter === "" || model.createdById === root.authorFilter)
                height: visible ? implicitHeight : 0
                onClicked: taskDetailRef.openFor(model)
            }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMed }
                NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: Theme.animMed; easing.type: Easing.OutCubic }
            }
        }
    }
}
