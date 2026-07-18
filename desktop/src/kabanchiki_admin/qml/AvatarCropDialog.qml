import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts

// Pan + zoom circular crop for avatars. Emits cropped(file, x, y, size) with
// the square crop rect in source-image pixels (orientation-corrected — the
// backend applies the same transpose before cutting).
AppDialog {
    id: root
    title: qsTr("Crop the photo")

    signal cropped(string fileUrl, real x, real y, real size)

    property string fileUrl: ""
    property int srcW: 0
    property int srcH: 0
    property real zoom: 1.0
    property real panX: 0
    property real panY: 0
    readonly property int frame: 300
    // cover-fit base scale × user zoom
    readonly property real scaleK: srcW > 0 ? Math.max(frame / srcW, frame / srcH) * zoom : 1

    function openFor(url) {
        fileUrl = url
        var size = backend.imageSize(url)
        srcW = size[0]; srcH = size[1]
        zoom = 1.0; panX = 0; panY = 0
        zoomSlider.value = 1.0
        if (srcW > 0) open()
    }

    function clampPan() {
        var maxX = Math.max(0, (srcW * scaleK - frame) / 2)
        var maxY = Math.max(0, (srcH * scaleK - frame) / 2)
        panX = Math.max(-maxX, Math.min(maxX, panX))
        panY = Math.max(-maxY, Math.min(maxY, panY))
    }

    function commit() {
        clampPan()
        var size = frame / scaleK
        var x = (srcW - size) / 2 - panX / scaleK
        var y = (srcH - size) / 2 - panY / scaleK
        root.close()
        root.cropped(fileUrl, x, y, size)
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingMd

        // circular viewport
        Item {
            Layout.alignment: Qt.AlignHCenter
            width: root.frame
            height: root.frame

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Theme.surfaceAlt
                border.width: 2
                border.color: Theme.accent
            }

            Item {
                id: viewport
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: cropMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 0.6
                }

                Image {
                    id: cropImage
                    source: root.fileUrl
                    x: (root.frame - width) / 2 + root.panX
                    y: (root.frame - height) / 2 + root.panY
                    width: root.srcW * root.scaleK
                    height: root.srcH * root.scaleK
                    autoTransform: true
                    smooth: true
                    mipmap: true
                }
            }

            Item {
                id: cropMask
                anchors.fill: parent
                layer.enabled: true
                visible: false
                Rectangle { anchors.fill: parent; radius: width / 2; color: "#FFFFFF" }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real sx: 0
                property real sy: 0
                property real bx: 0
                property real by: 0
                onPressed: function(mouse) { sx = mouse.x; sy = mouse.y; bx = root.panX; by = root.panY }
                onPositionChanged: function(mouse) {
                    if (!pressed) return
                    root.panX = bx + (mouse.x - sx)
                    root.panY = by + (mouse.y - sy)
                    root.clampPan()
                }
                onWheel: function(wheel) {
                    var step = wheel.angleDelta.y > 0 ? 1.1 : 1 / 1.1
                    root.zoom = Math.max(1.0, Math.min(4.0, root.zoom * step))
                    zoomSlider.value = root.zoom
                    root.clampPan()
                }
            }
        }

        // zoom slider
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Text { text: "－"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeMd }
            Slider {
                id: zoomSlider
                Layout.fillWidth: true
                from: 1.0
                to: 4.0
                value: 1.0
                onMoved: { root.zoom = value; root.clampPan() }

                background: Rectangle {
                    x: zoomSlider.leftPadding
                    y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                    width: zoomSlider.availableWidth
                    height: 4
                    radius: 2
                    color: Theme.border
                    Rectangle {
                        width: zoomSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                    }
                }
                handle: Rectangle {
                    x: zoomSlider.leftPadding + zoomSlider.visualPosition * (zoomSlider.availableWidth - width)
                    y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                    width: 20; height: 20; radius: 10
                    color: "#FFFFFF"
                    border.width: 1
                    border.color: Theme.border
                    scale: zoomSlider.pressed ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                }
            }
            Text { text: "＋"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeMd }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Drag to position · scroll or slide to zoom")
            font.pixelSize: Theme.fontSizeXs
            color: Theme.textSecondary
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: root.close() }
            AppButton { text: qsTr("Done"); onClicked: root.commit() }
        }
    }
}
