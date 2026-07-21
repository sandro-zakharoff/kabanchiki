import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

AppDialog {
    id: root
    title: editJobId.length > 0 ? qsTr("Edit job") : qsTr("New hourly job")
    width: 500

    property var checkedChildren: ({})
    property string editJobId: ""

    acceptAction: function() { root.save() }

    function canSave() {
        return titleField.text.trim().length > 0
            && rateField.text.length > 0
            && root.selectedIds().length > 0
    }

    function save() {
        if (!canSave()) return
        var fields = {
            title: titleField.text.trim(),
            description: descArea.text,
            hourly_rate: parseInt(rateField.text, 10)
        }
        if (root.editJobId.length > 0) {
            backend.updateJob(root.editJobId, fields, root.selectedIds())
        } else {
            backend.createJob(fields, root.selectedIds())
        }
        root.close()
    }

    function openForCreate() {
        editJobId = ""
        titleField.text = ""
        descArea.text = ""
        rateField.text = ""
        checkedChildren = ({})
        childrenRepeater.model = backend.childrenModel.all()
        open()
    }

    function openForEdit(job) {
        editJobId = job.jobId
        titleField.text = job.title
        descArea.text = job.description
        rateField.text = String(job.rate)
        var map = {}
        for (var i = 0; i < job.membersVar.length; i++)
            map[job.membersVar[i].childId] = true
        checkedChildren = map
        childrenRepeater.model = backend.childrenModel.all()
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

    contentItem: ColumnLayout {
        spacing: Theme.spacingMd

        Text { text: qsTr("Participants"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Repeater {
                id: childrenRepeater
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool checked: root.checkedChildren[modelData.childId] === true
                    height: 36
                    width: nameLabel.implicitWidth + 24
                    radius: 18
                    color: checked ? modelData.color : Theme.surfaceAlt
                    border.width: 1
                    border.color: checked ? modelData.color : Theme.border
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        id: nameLabel
                        anchors.centerIn: parent
                        text: modelData.displayName
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Font.DemiBold
                        color: checked ? "#FFFFFF" : Theme.textPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
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

        Text { text: qsTr("Title"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        AppTextField {
            id: titleField
            Layout.fillWidth: true
            placeholderText: qsTr("e.g. Help in the workshop")
        }

        Text { text: qsTr("Description"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
        Rectangle {
            Layout.fillWidth: true
            height: 70
            radius: Theme.radiusSm
            color: Theme.surfaceAlt
            border.width: descArea.activeFocus ? 2 : 1
            border.color: descArea.activeFocus ? Theme.accent : Theme.border

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

        ColumnLayout {
            spacing: Theme.spacingXs
            Text { text: qsTr("Rate, acorns/hour"); font.pixelSize: Theme.fontSizeSm; font.weight: Font.DemiBold; color: Theme.textSecondary }
            AppTextField {
                id: rateField
                Layout.preferredWidth: 160
                placeholderText: "0"
                validator: IntValidator { bottom: 0 }
            }
            Text {
                text: qsTr("Earnings go to the assignee's personal balance automatically.")
                font.pixelSize: Theme.fontSizeXs
                color: Theme.textSecondary
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton {
                text: root.editJobId.length > 0 ? qsTr("Save") : qsTr("Create job")
                enabled: root.canSave()
                onClicked: root.save()
            }
        }
    }
}
