import QtQuick
import QtQuick.Controls.Basic

// Full-window image viewer that stacks above any open dialog (it's a Popup on
// the overlay layer). show(url) / showList(urls, index) open it; ‹ › or the
// arrow keys page through a gallery, scroll zooms, drag pans, double-click
// toggles fit/2×, click the backdrop or Esc / × closes.
Popup {
    id: root
    parent: Overlay.overlay
    modal: true
    dim: false
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0

    property real minZoom: 1.0
    property real maxZoom: 6.0
    property real zoom: 1.0
    property real panX: 0
    property real panY: 0

    property var urls: []
    property int current: 0

    function show(url) { showList([url], 0) }

    function showList(list, index) {
        urls = list || []
        if (urls.length === 0) return
        current = Math.max(0, Math.min(urls.length - 1, index || 0))
        img.source = urls[current]
        zoom = 1.0; panX = 0; panY = 0
        open()
    }

    function step(delta) {
        if (urls.length < 2) return
        current = (current + delta + urls.length) % urls.length
        img.source = urls[current]
        zoom = 1.0; panX = 0; panY = 0
    }

    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMed } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.animFast } }

    Behavior on zoom { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    background: Rectangle { color: "#EE141014" }

    contentItem: Item {
        focus: true
        Keys.onLeftPressed: root.step(-1)
        Keys.onRightPressed: root.step(1)

        Image {
            id: img
            anchors.centerIn: parent
            width: Math.min(parent.width - 120, sourceSize.width)
            height: Math.min(parent.height - 140, sourceSize.height)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            transformOrigin: Item.Center
            scale: root.zoom
            transform: Translate { x: root.panX; y: root.panY }

            // subtle cross-fade when paging
            opacity: status === Image.Ready ? 1 : 0.35
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }

        BusyIndicator {
            anchors.centerIn: parent
            running: img.status === Image.Loading
            width: 42; height: 42
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: root.zoom > 1.0 ? Qt.OpenHandCursor : Qt.ArrowCursor
            property real startX: 0
            property real startY: 0
            property real baseX: 0
            property real baseY: 0
            property bool moved: false
            onPressed: function(mouse) {
                startX = mouse.x; startY = mouse.y
                baseX = root.panX; baseY = root.panY; moved = false
            }
            onPositionChanged: function(mouse) {
                if (pressed && root.zoom > 1.0) {
                    root.panX = baseX + (mouse.x - startX)
                    root.panY = baseY + (mouse.y - startY)
                    if (Math.abs(mouse.x - startX) + Math.abs(mouse.y - startY) > 4) moved = true
                }
            }
            onClicked: if (!moved && root.zoom <= 1.001) root.close()
            onDoubleClicked: {
                if (root.zoom > 1.0) { root.zoom = 1.0; root.panX = 0; root.panY = 0 }
                else root.zoom = 2.0
            }
            onWheel: function(wheel) {
                var step = wheel.angleDelta.y > 0 ? 1.18 : 1 / 1.18
                root.zoom = Math.max(root.minZoom, Math.min(root.maxZoom, root.zoom * step))
                if (root.zoom <= root.minZoom) { root.panX = 0; root.panY = 0 }
            }
        }

        // paging arrows (galleries only)
        Rectangle {
            visible: root.urls.length > 1
            width: 46; height: 46; radius: 23
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 18
            color: prevHover.hovered ? "#44FFFFFF" : "#22FFFFFF"
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Text { anchors.centerIn: parent; text: "‹"; color: "#FFFFFF"; font.pixelSize: 24 }
            HoverHandler { id: prevHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.step(-1) }
        }
        Rectangle {
            visible: root.urls.length > 1
            width: 46; height: 46; radius: 23
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 18
            color: nextHover.hovered ? "#44FFFFFF" : "#22FFFFFF"
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Text { anchors.centerIn: parent; text: "›"; color: "#FFFFFF"; font.pixelSize: 24 }
            HoverHandler { id: nextHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.step(1) }
        }

        Rectangle {
            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 18
            width: 40; height: 40; radius: 20
            color: closeHover.hovered ? "#33FFFFFF" : "#22FFFFFF"
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Text { anchors.centerIn: parent; text: "✕"; color: "#FFFFFF"; font.pixelSize: 18 }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.close() }
        }

        // counter
        Rectangle {
            visible: root.urls.length > 1
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 24
            width: counterText.implicitWidth + 24
            height: 30
            radius: 15
            color: "#33000000"
            Text {
                id: counterText
                anchors.centerIn: parent
                text: (root.current + 1) + " / " + root.urls.length
                color: "#FFFFFF"
                font.pixelSize: Theme.fontSizeSm
                font.weight: Font.Bold
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 22
            text: qsTr("Scroll to zoom · drag to move · double-click to reset")
            color: "#B0FFFFFF"; font.pixelSize: Theme.fontSizeSm
        }
    }
}
