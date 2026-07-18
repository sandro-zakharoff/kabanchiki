import QtQuick
import QtQuick.Layouts

// Tri-state presence: active (in app now) / reachable (push will arrive) / offline.
RowLayout {
    id: root
    property string presence: "offline" // active | reachable | offline

    spacing: 5

    readonly property color dotColor: presence === "active" ? Theme.success
        : presence === "reachable" ? Theme.info : Theme.textSecondary
    readonly property string label: presence === "active" ? qsTr("in app")
        : presence === "reachable" ? qsTr("reachable") : qsTr("offline")
    readonly property string glyph: presence === "reachable" ? "🔔" : ""

    Rectangle {
        visible: root.presence !== "reachable"
        width: 8; height: 8; radius: 4
        color: root.dotColor
        Behavior on color { ColorAnimation { duration: Theme.animMed } }
    }
    Text {
        visible: root.glyph.length > 0
        text: root.glyph
        font.pixelSize: Theme.fontSizeXs
    }
    Text {
        text: root.label
        font.pixelSize: Theme.fontSizeXs
        color: root.dotColor
    }
}
