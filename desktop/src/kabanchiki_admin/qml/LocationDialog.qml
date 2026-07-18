import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtLocation
import QtPositioning

// Where is the assignee: OpenStreetMap with the latest point, short history
// and the exact coordinates. Free OSM tiles — no API keys involved.
AppDialog {
    id: root
    width: 640

    property string childId: ""
    property var points: []          // newest first: {lat, lng, accuracy, locality, timeText}
    readonly property var latest: points.length > 0 ? points[0] : null

    function openFor(id, name) {
        childId = id
        points = backend.locationHistory(id)
        title = qsTr("Location — %1").arg(name)
        subtitle = latest
            ? (latest.locality.length > 0 ? latest.locality + " · " : "") + latest.timeText
            : qsTr("No location data yet")
        open()
        if (latest) map.center = QtPositioning.coordinate(latest.lat, latest.lng)
    }

    contentItem: ColumnLayout {
        implicitWidth: 592
        spacing: Theme.spacingMd

        // Empty state: geolocation off / never reported.
        ColumnLayout {
            visible: !root.latest
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Layout.topMargin: Theme.spacingLg
            Layout.bottomMargin: Theme.spacingLg
            Text {
                text: "📍"
                font.pixelSize: 40
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: qsTr("No data yet. Geolocation is enabled by the assignee on the phone:\nProfile → Geolocation. Points arrive about every 15 minutes.")
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
        }

        Rectangle {
            visible: root.latest !== null
            Layout.fillWidth: true
            Layout.preferredHeight: 340
            radius: Theme.radiusSm
            clip: true
            color: Theme.surfaceAlt
            border.width: 1
            border.color: Theme.border

            Map {
                id: map
                anchors.fill: parent
                plugin: Plugin {
                    name: "osm"
                    PluginParameter { name: "osm.useragent"; value: "Kabanchiki/1.7 (family app)" }
                    // Plain openstreetmap.org tiles — the default keyed providers
                    // stamp an "API Key Required" watermark.
                    PluginParameter { name: "osm.mapping.custom.host"; value: "https://tile.openstreetmap.org/" }
                }
                zoomLevel: 15
                copyrightsVisible: true

                // The custom host appears as the last supported map type. The
                // provider list can arrive after creation (slower cold start in
                // the packaged exe), so react to the change too.
                function pickCustomProvider() {
                    if (supportedMapTypes.length > 0)
                        activeMapType = supportedMapTypes[supportedMapTypes.length - 1]
                }
                Component.onCompleted: pickCustomProvider()
                onSupportedMapTypesChanged: pickCustomProvider()

                // pinch/wheel/drag control
                PinchHandler { target: null; onScaleChanged: (delta) => { map.zoomLevel += Math.log2(delta) } }
                WheelHandler {
                    onWheel: (event) => { map.zoomLevel += event.angleDelta.y > 0 ? 0.5 : -0.5 }
                }
                DragHandler {
                    target: null
                    onTranslationChanged: (delta) => map.pan(-delta.x, -delta.y)
                }

                // History trail (oldest → newest).
                MapPolyline {
                    line.width: 3
                    line.color: Qt.alpha(Theme.accent, 0.55)
                    path: {
                        var p = []
                        for (var i = root.points.length - 1; i >= 0; i--)
                            p.push(QtPositioning.coordinate(root.points[i].lat, root.points[i].lng))
                        return p
                    }
                }

                // Latest point marker.
                MapQuickItem {
                    visible: root.latest !== null
                    coordinate: root.latest
                        ? QtPositioning.coordinate(root.latest.lat, root.latest.lng)
                        : QtPositioning.coordinate(0, 0)
                    anchorPoint.x: 14
                    anchorPoint.y: 34
                    sourceItem: Column {
                        spacing: 0
                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: Theme.accent
                            border.width: 3
                            border.color: "#FFFFFF"
                            Text { anchors.centerIn: parent; text: "📍"; font.pixelSize: 13 }
                        }
                        Item { width: 1; height: 6 }
                    }
                }
            }
        }

        RowLayout {
            visible: root.latest !== null
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Text {
                text: root.latest
                    ? qsTr("Coordinates: %1, %2 · accuracy ~%3 m")
                        .arg(root.latest.lat.toFixed(5)).arg(root.latest.lng.toFixed(5))
                        .arg(Math.round(root.latest.accuracy))
                    : ""
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
                Layout.fillWidth: true
            }
            AppButton {
                small: true
                variant: "secondary"
                text: qsTr("Copy")
                onClicked: backend.copyToClipboard(
                    root.latest.lat.toFixed(6) + ", " + root.latest.lng.toFixed(6))
            }
        }

        // Short history list.
        ColumnLayout {
            visible: root.points.length > 1
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: qsTr("History (last %1 points)").arg(root.points.length)
                font.pixelSize: Theme.fontSizeXs
                font.weight: Font.Bold
                color: Theme.textSecondary
            }
            Repeater {
                model: root.points.slice(0, 8)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Text {
                        text: modelData.timeText
                        font.pixelSize: Theme.fontSizeXs
                        color: Theme.textSecondary
                        Layout.preferredWidth: 130
                    }
                    Text {
                        text: modelData.locality.length > 0
                            ? modelData.locality
                            : modelData.lat.toFixed(5) + ", " + modelData.lng.toFixed(5)
                        font.pixelSize: Theme.fontSizeXs
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Close"); variant: "secondary"; onClicked: root.close() }
        }
    }
}
