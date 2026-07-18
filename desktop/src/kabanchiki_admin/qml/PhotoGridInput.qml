import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts

// Multi-photo input for task forms: existing server attachments (removable),
// freshly picked local files (removable), and an "add" tile. The caller reads
// `localFiles` and `removedIds` on save; photos are optimized before upload.
Item {
    id: root

    // [{attId, thumbUrl}] — current server photos when editing.
    property var existingPhotos: []
    property var localFiles: []   // ["file:///…"]
    property var removedIds: []   // attIds marked for removal
    property int maxPhotos: 10

    readonly property int totalCount: existingPhotos.length - removedIds.length + localFiles.length

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    function reset(photos) {
        existingPhotos = photos || []
        localFiles = []
        removedIds = []
    }

    FileDialog {
        id: picker
        fileMode: FileDialog.OpenFiles
        nameFilters: [qsTr("Images (*.jpg *.jpeg *.png *.webp)")]
        onAccepted: {
            var files = root.localFiles.slice()
            for (var i = 0; i < selectedFiles.length; i++) {
                if (root.totalCount + (files.length - root.localFiles.length) >= root.maxPhotos) break
                files.push(selectedFiles[i].toString())
            }
            root.localFiles = files
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacingXs

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            // server photos (edit mode)
            Repeater {
                model: root.existingPhotos
                delegate: Item {
                    required property var modelData
                    visible: root.removedIds.indexOf(modelData.attId) === -1
                    width: 88; height: 88

                    ImageThumb {
                        anchors.fill: parent
                        source: modelData.thumbUrl
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 4
                        width: 22; height: 22; radius: 11
                        color: exRm.hovered ? Theme.danger : "#99141014"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text { anchors.centerIn: parent; text: "✕"; color: "#FFFFFF"; font.pixelSize: 10; font.weight: Font.Bold }
                        HoverHandler { id: exRm; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                var ids = root.removedIds.slice()
                                ids.push(modelData.attId)
                                root.removedIds = ids
                            }
                        }
                    }
                }
            }

            // freshly picked local files
            Repeater {
                model: root.localFiles
                delegate: Item {
                    required property string modelData
                    required property int index
                    width: 88; height: 88

                    ImageThumb {
                        anchors.fill: parent
                        source: modelData
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 4
                        width: 22; height: 22; radius: 11
                        color: locRm.hovered ? Theme.danger : "#99141014"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text { anchors.centerIn: parent; text: "✕"; color: "#FFFFFF"; font.pixelSize: 10; font.weight: Font.Bold }
                        HoverHandler { id: locRm; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                var files = root.localFiles.slice()
                                files.splice(index, 1)
                                root.localFiles = files
                            }
                        }
                    }
                }
            }

            // add tile
            Rectangle {
                visible: root.totalCount < root.maxPhotos
                width: 88; height: 88
                radius: Theme.radiusSm
                color: addHover.hovered ? Theme.surfaceAlt : Qt.alpha(Theme.surfaceAlt, 0.4)
                border.width: 1.5
                border.color: addHover.hovered ? Theme.accent : Theme.border
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2
                    Text {
                        text: "＋"
                        font.pixelSize: 22
                        color: addHover.hovered ? Theme.accent : Theme.textSecondary
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: qsTr("Add")
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Font.DemiBold
                        color: addHover.hovered ? Theme.accent : Theme.textSecondary
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
                HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: picker.open() }
            }
        }

        Text {
            text: qsTr("Up to %1 photos — compressed automatically, EXIF/GPS removed").arg(root.maxPhotos)
            font.pixelSize: Theme.fontSizeXs
            color: Theme.textSecondary
        }
    }
}
