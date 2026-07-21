import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppDialog {
    id: root
    title: editTaskId.length > 0 ? qsTr("Edit task") : qsTr("New task")

    property var checkedChildren: ({})
    property int difficulty: 1
    property string editTaskId: ""
    property string completionMode: "timer" // timer | simple

    readonly property int formWidth: 540

    acceptAction: function() { root.save() }

    function canSave() {
        return titleField.text.trim().length > 0
            && amountField.text.length > 0
            && (root.editTaskId.length > 0 || root.selectedIds().length > 0)
    }

    function save() {
        if (!canSave()) return
        var deadline = deadlineField.deadlineIso
        // Not-in-the-past only on creation.
        if (root.editTaskId.length === 0 && deadline.length > 0
            && new Date(deadline).getTime() <= Date.now()) {
            deadlineErr.visible = true; return
        }
        deadlineErr.visible = false
        var fields = {
            title: titleField.text.trim(),
            description: descArea.text,
            completion_mode: root.completionMode,
            reward_type: rewardCombo.model[rewardCombo.currentIndex].value,
            reward_amount: parseInt(amountField.text, 10),
            difficulty: root.difficulty,
            requirements: reqArea.text,
            proof_text: proofTextCombo.model[proofTextCombo.currentIndex].value,
            proof_photo: proofPhotoCombo.model[proofPhotoCombo.currentIndex].value,
            deadline_at: deadline.length > 0 ? deadline : null,
            photo_files: photoGrid.localFiles
        }
        if (root.editTaskId.length > 0) {
            fields.attachments_remove = photoGrid.removedIds
            backend.updateTask(root.editTaskId, fields)
        } else {
            fields.child_ids = root.selectedIds()
            backend.createTask(fields)
        }
        root.close()
    }

    function openForCreate() {
        editTaskId = ""
        titleField.text = ""
        descArea.text = ""
        amountField.text = ""
        reqArea.text = ""
        rewardCombo.currentIndex = 0
        proofTextCombo.currentIndex = 0
        proofPhotoCombo.currentIndex = 0
        difficulty = 1
        completionMode = "timer"
        deadlineField.deadlineIso = ""
        photoGrid.reset([])
        deadlineErr.visible = false
        checkedChildren = ({})
        childrenRepeater.model = backend.childrenModel.all()
        open()
    }

    function openForEdit(task) {
        editTaskId = task.taskId
        titleField.text = task.title
        descArea.text = task.description
        amountField.text = String(task.rewardAmount)
        reqArea.text = task.requirements
        completionMode = task.completionMode ? task.completionMode : "timer"
        rewardCombo.currentIndex = task.rewardType === "hourly" ? 1 : 0
        proofTextCombo.currentIndex = task.proofText === "required" ? 2 : (task.proofText === "optional" ? 1 : 0)
        proofPhotoCombo.currentIndex = task.proofPhoto === "required" ? 2 : (task.proofPhoto === "optional" ? 1 : 0)
        difficulty = task.difficulty
        deadlineField.deadlineIso = task.deadlineIso || ""
        photoGrid.reset(task.photosVar || [])
        deadlineErr.visible = false
        checkedChildren = ({})
        childrenRepeater.model = []
        open()
    }

    function selectedIds() {
        var ids = []
        var rows = backend.childrenModel.all()
        for (var i = 0; i < rows.length; i++)
            if (checkedChildren[rows[i].childId] === true)
                ids.push(rows[i].childId)
        return ids
    }

    component FieldLabel: Text {
        font.pixelSize: Theme.fontSizeSm
        font.weight: Font.DemiBold
        color: Theme.textSecondary
    }

    contentItem: Flickable {
        implicitWidth: root.formWidth
        implicitHeight: Math.min(formCol.implicitHeight, root.maxContentHeight)
        contentHeight: formCol.implicitHeight
        contentWidth: width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: formCol
            width: root.formWidth
            spacing: Theme.spacingMd

            FieldLabel { visible: root.editTaskId.length === 0; text: qsTr("Assignees") }
            Flow {
                visible: root.editTaskId.length === 0
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                Repeater {
                    id: childrenRepeater
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool checked: root.checkedChildren[modelData.childId] === true
                        height: 36
                        width: childLabel.implicitWidth + 40
                        radius: 18
                        color: checked ? modelData.color : Theme.surfaceAlt
                        border.width: 1
                        border.color: checked ? modelData.color : Theme.border
                        Behavior on color { ColorAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: checked ? "✓" : "＋"
                                font.pixelSize: Theme.fontSizeSm
                                color: checked ? "#FFFFFF" : Theme.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                id: childLabel
                                text: modelData.displayName
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: Font.DemiBold
                                color: checked ? "#FFFFFF" : Theme.textPrimary
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var map = root.checkedChildren
                                map[modelData.childId] = !(map[modelData.childId] === true)
                                root.checkedChildren = map
                                root.checkedChildrenChanged()
                            }
                        }
                    }
                }
            }

            FieldLabel { text: qsTr("Title") }
            AppTextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: qsTr("e.g. Clean your room")
            }

            FieldLabel { text: qsTr("Description") }
            Rectangle {
                Layout.fillWidth: true
                height: 84
                radius: Theme.radiusSm
                color: Theme.surfaceAlt
                border.width: descArea.activeFocus ? 2 : 1
                border.color: descArea.activeFocus ? Theme.accent : Theme.border
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 4
                    TextArea {
                        id: descArea
                        wrapMode: TextArea.Wrap
                        font.pixelSize: Theme.fontSizeMd
                        color: Theme.textPrimary
                        background: null
                    }
                }
            }

            // How the task is completed.
            FieldLabel { text: qsTr("How it's completed") }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                Repeater {
                    model: [
                        { value: "timer", title: qsTr("With a timer"), hint: qsTr("Start → timer runs → Done") },
                        { value: "simple", title: qsTr("Instant Done"), hint: qsTr("No timer, just a Done button") }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: root.completionMode === modelData.value
                        Layout.fillWidth: true
                        Layout.preferredHeight: 54
                        radius: Theme.radiusSm
                        color: active ? Qt.alpha(Theme.accent, 0.12) : Theme.surfaceAlt
                        border.width: active ? 2 : 1
                        border.color: active ? Theme.accent : Theme.border
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                text: modelData.title
                                font.pixelSize: Theme.fontSizeMd
                                font.weight: Font.DemiBold
                                color: active ? Theme.accent : Theme.textPrimary
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: modelData.hint
                                font.pixelSize: Theme.fontSizeXs
                                color: Theme.textSecondary
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.completionMode = modelData.value
                                // Hourly pay needs a timer.
                                if (modelData.value === "simple") rewardCombo.currentIndex = 0
                            }
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.spacingMd
                rowSpacing: Theme.spacingXs

                FieldLabel { text: qsTr("Reward") }
                FieldLabel {
                    text: rewardCombo.currentIndex === 0 ? qsTr("Amount, acorns") : qsTr("Rate, acorns/hour")
                }

                AppComboBox {
                    id: rewardCombo
                    Layout.fillWidth: true
                    textRole: "label"
                    // Hourly is only offered for timer tasks.
                    model: root.completionMode === "simple"
                        ? [{ label: qsTr("Fixed amount"), value: "fixed" }]
                        : [{ label: qsTr("Fixed amount"), value: "fixed" },
                           { label: qsTr("Per hour of work"), value: "hourly" }]
                }
                AppTextField {
                    id: amountField
                    Layout.fillWidth: true
                    placeholderText: "0"
                    validator: IntValidator { bottom: 0 }
                }
            }

            FieldLabel { text: qsTr("Difficulty") }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                Repeater {
                    model: 5
                    delegate: Rectangle {
                        required property int index
                        readonly property int level: index + 1
                        readonly property var colors: ["#6FA287", "#8598B5", "#D99A5B", "#CE8158", "#C96A5F"]
                        readonly property bool active: root.difficulty === level
                        Layout.fillWidth: true
                        height: 34
                        radius: 17
                        color: active ? colors[index] : Qt.alpha(colors[index], 0.13)
                        Behavior on color { ColorAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: [qsTr("Very easy"), qsTr("Easy"), qsTr("Medium"), qsTr("Hard"), qsTr("Very hard")][index]
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Font.DemiBold
                            color: active ? "#FFFFFF" : colors[index]
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.difficulty = level
                        }
                    }
                }
            }

            FieldLabel { text: qsTr("Deadline (optional)") }
            DeadlineField {
                id: deadlineField
                Layout.preferredWidth: 280
                onDeadlineIsoChanged: deadlineErr.visible = false
            }
            Text {
                id: deadlineErr
                visible: false
                text: qsTr("The deadline can't be in the past")
                font.pixelSize: Theme.fontSizeXs
                color: Theme.danger
            }

            FieldLabel { text: qsTr("Extra requirements (the assignee sees them)") }
            Rectangle {
                Layout.fillWidth: true
                height: 64
                radius: Theme.radiusSm
                color: Theme.surfaceAlt
                border.width: reqArea.activeFocus ? 2 : 1
                border.color: reqArea.activeFocus ? Theme.accent : Theme.border
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 4
                    TextArea {
                        id: reqArea
                        wrapMode: TextArea.Wrap
                        font.pixelSize: Theme.fontSizeMd
                        color: Theme.textPrimary
                        background: null
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.spacingMd
                rowSpacing: Theme.spacingXs

                FieldLabel { text: qsTr("Text from assignee") }
                FieldLabel { text: qsTr("Photo from assignee") }

                AppComboBox {
                    id: proofTextCombo
                    Layout.fillWidth: true
                    textRole: "label"
                    model: [
                        { label: qsTr("Not needed"), value: "none" },
                        { label: qsTr("Optional"), value: "optional" },
                        { label: qsTr("Required"), value: "required" }
                    ]
                }
                AppComboBox {
                    id: proofPhotoCombo
                    Layout.fillWidth: true
                    textRole: "label"
                    model: [
                        { label: qsTr("Not needed"), value: "none" },
                        { label: qsTr("Optional"), value: "optional" },
                        { label: qsTr("Required"), value: "required" }
                    ]
                }
            }

            FieldLabel { text: qsTr("Task photos") }
            PhotoGridInput {
                id: photoGrid
                Layout.fillWidth: true
            }

            Item { height: Theme.spacingXs }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                Item { Layout.fillWidth: true }
                AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
                AppButton {
                    text: root.editTaskId.length > 0 ? qsTr("Save") : qsTr("Create task")
                    enabled: root.canSave()
                    onClicked: root.save()
                }
            }
        }
    }
}
