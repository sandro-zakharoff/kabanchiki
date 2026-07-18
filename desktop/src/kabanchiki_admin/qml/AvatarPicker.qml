import QtQuick
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts

// Avatar chooser for the child dialogs: preview + "choose photo" (opens the
// crop dialog) + "remove". The dialog reads pendingFile/pendingCrop/cleared
// on save and passes them to the backend.
Item {
    id: root

    property string name: ""
    property string color: "#CDB1B1"
    property string currentUrl: ""   // avatar already on the server

    property string pendingFile: ""  // freshly cropped local file ("" = unchanged)
    property var pendingCrop: null   // {x, y, size} in source pixels
    property bool cleared: false

    implicitHeight: row.implicitHeight
    implicitWidth: row.implicitWidth

    function reset(url) {
        currentUrl = url || ""
        pendingFile = ""
        pendingCrop = null
        cleared = false
    }

    readonly property bool showsPhoto: pendingFile.length > 0 || (!cleared && currentUrl.length > 0)

    FileDialog {
        id: fileDialog
        nameFilters: [qsTr("Images (*.jpg *.jpeg *.png *.webp)")]
        onAccepted: cropDialog.openFor(selectedFile.toString())
    }

    AvatarCropDialog {
        id: cropDialog
        onCropped: function(fileUrl, x, y, size) {
            root.pendingFile = fileUrl
            root.pendingCrop = { x: x, y: y, size: size }
            root.cleared = false
        }
    }

    RowLayout {
        id: row
        spacing: Theme.spacingMd

        // preview: cropped local file > server photo > initials
        Item {
            width: 72; height: 72

            Avatar {
                anchors.fill: parent
                visible: root.pendingFile.length === 0
                name: root.name
                color: root.color
                size: 72
                source: root.cleared ? "" : root.currentUrl
            }

            Image {
                id: pendingPreview
                anchors.fill: parent
                visible: root.pendingFile.length > 0
                source: root.pendingFile
                autoTransform: true
                fillMode: Image.Pad
                sourceClipRect: root.pendingCrop
                    ? Qt.rect(root.pendingCrop.x, root.pendingCrop.y,
                              root.pendingCrop.size, root.pendingCrop.size)
                    : Qt.rect(0, 0, 0, 0)
                // scale the clipped square down to the 72px preview
                transform: Scale {
                    xScale: root.pendingCrop ? 72 / root.pendingCrop.size : 1
                    yScale: root.pendingCrop ? 72 / root.pendingCrop.size : 1
                }
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: previewMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 0.6
                }
            }
            Item {
                id: previewMask
                anchors.fill: parent
                layer.enabled: true
                visible: false
                Rectangle { anchors.fill: parent; radius: 36; color: "#FFFFFF" }
            }
        }

        ColumnLayout {
            spacing: Theme.spacingXs
            AppButton {
                small: true
                variant: "secondary"
                text: root.showsPhoto ? qsTr("Change photo…") : qsTr("Add photo…")
                onClicked: fileDialog.open()
            }
            AppButton {
                small: true
                variant: "ghost"
                visible: root.showsPhoto
                text: qsTr("Remove photo")
                onClicked: {
                    root.pendingFile = ""
                    root.pendingCrop = null
                    root.cleared = true
                }
            }
        }
    }
}
