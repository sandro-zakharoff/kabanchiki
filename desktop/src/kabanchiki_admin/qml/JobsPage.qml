import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: qsTr("Hourly jobs")
                font.pixelSize: Theme.fontSizeXl
                font.weight: Font.Bold
                color: Theme.textPrimary
            }
            Item { Layout.fillWidth: true }
            AppButton {
                text: qsTr("+ New job")
                onClicked: jobDialogRef.openForCreate()
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.spacingMd
            model: backend.jobsModel

            ColumnLayout {
                anchors.centerIn: parent
                visible: list.count === 0
                spacing: Theme.spacingSm
                Text {
                    text: "⏱️"
                    font.pixelSize: 40
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: qsTr("No hourly jobs")
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: qsTr("An hourly job is a shared timer you start and stop; assignees earn per hour")
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textSecondary
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            delegate: Card {
                width: list.width
                implicitHeight: jobCol.implicitHeight + Theme.spacingLg * 2

                ColumnLayout {
                    id: jobCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.spacingLg
                    anchors.rightMargin: Theme.spacingLg
                    spacing: Theme.spacingMd

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm

                        ColumnLayout {
                            spacing: 2

                            RowLayout {
                                spacing: Theme.spacingSm

                                Text {
                                    text: model.title
                                    font.pixelSize: Theme.fontSizeLg
                                    font.weight: Font.Bold
                                    color: Theme.textPrimary
                                }

                                Chip {
                                    text: model.running ? qsTr("Running") : qsTr("Stopped")
                                    chipColor: model.running ? Theme.success : Theme.textSecondary
                                    filled: model.running
                                }
                            }

                            AcornAmount {
                                text: model.rateText
                                suffix: qsTr("/ hour")
                                fontSize: Theme.fontSizeSm
                                fontWeight: Font.Normal
                                color: Theme.textSecondary
                            }

                            Text {
                                visible: model.description.length > 0
                                text: model.description
                                font.pixelSize: Theme.fontSizeSm
                                color: Theme.textSecondary
                                wrapMode: Text.WordWrap
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 2

                            Text {
                                text: model.totalText
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight

                                font.pixelSize: Theme.fontSizeXxl
                                font.weight: Font.Bold
                                font.family: "Consolas"
                                color: model.running ? Theme.accent : Theme.textPrimary
                            }

                            Text {
                                text: qsTr("total time")
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight

                                font.pixelSize: Theme.fontSizeXs
                                color: Theme.textSecondary
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                    // members
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.marginMd
                        spacing: Theme.spacingSm

                        Repeater {
                            model: membersVar
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.spacingSm

                                Avatar { name: modelData.name; color: modelData.color; size: 30; source: modelData.avatarUrl || "" }
                                Text {
                                    text: modelData.name
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Font.DemiBold
                                    color: Theme.textPrimary
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: qsTr("earned")
                                    font.pixelSize: Theme.fontSizeXs
                                    color: Theme.textSecondary
                                }
                                AcornAmount {
                                    text: modelData.earnedText
                                    fontSize: Theme.fontSizeLg
                                    fontWeight: Font.Bold
                                    fontFamily: "Consolas"
                                        color: modelData.earned > 0 ? Theme.accent : Theme.textSecondary
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.marginMd
                        spacing: Theme.spacingSm
                        AppButton {
                            text: qsTr("Edit")
                            variant: "ghost"
                            onClicked: jobDialogRef.openForEdit({
                                jobId: model.jobId,
                                title: model.title,
                                description: model.description,
                                rate: model.rate,
                                membersVar: model.membersVar
                            })
                        }
                        AppButton {
                            text: qsTr("Delete")
                            variant: "danger"
                            onClicked: confirmRef.openWith(
                                qsTr("Delete job"),
                                qsTr("The job “%1” and its whole history will be deleted for everyone. Delete?").arg(model.title),
                                function() { backend.deleteJob(model.jobId) },
                                true)
                        }
                        Item { Layout.fillWidth: true }
                        AppButton {
                            text: model.running ? qsTr("Stop") : qsTr("Start")
                            variant: model.running ? "secondary" : "primary"
                            onClicked: model.running ? backend.jobStop(model.jobId) : backend.jobStart(model.jobId)
                        }
                        AppButton {
                            text: qsTr("Finish job")
                            variant: "ghost"
                            onClicked: confirmRef.openWith(
                                qsTr("Finish job"),
                                qsTr("The job “%1” will be stopped and hidden from everyone. Continue?").arg(model.title),
                                function() { backend.jobArchive(model.jobId) },
                                true)
                        }
                    }
                }
            }
        }
    }
}
