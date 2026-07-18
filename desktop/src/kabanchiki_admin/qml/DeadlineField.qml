import QtQuick
import QtQuick.Layouts

// Deadline input: looks like a field, opens the calendar/time picker, and —
// once a deadline is set — offers an obvious inline "×" to clear it.
Item {
    id: root
    property string deadlineIso: "" // "" = no deadline

    implicitHeight: 40
    implicitWidth: 260

    function displayText() {
        if (deadlineIso.length === 0) return ""
        var d = new Date(deadlineIso)
        if (isNaN(d.getTime())) return ""
        function two(n) { return (n < 10 ? "0" : "") + n }
        return two(d.getDate()) + "." + two(d.getMonth() + 1) + "." + d.getFullYear()
             + " " + two(d.getHours()) + ":" + two(d.getMinutes())
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Theme.surfaceAlt
        border.width: fieldHover.hovered ? 2 : 1
        border.color: fieldHover.hovered ? Theme.accent : Theme.border
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 8

            Text {
                text: "🗓"
                font.pixelSize: Theme.fontSizeMd
                opacity: 0.75
            }
            Text {
                Layout.fillWidth: true
                text: root.deadlineIso.length > 0 ? root.displayText() : qsTr("No deadline")
                font.pixelSize: Theme.fontSizeMd
                color: root.deadlineIso.length > 0 ? Theme.textPrimary : Theme.textSecondary
                elide: Text.ElideRight
            }

            // Clear affordance — always visible while a deadline is set.
            Rectangle {
                visible: root.deadlineIso.length > 0
                width: 24; height: 24; radius: 12
                color: clearHover.hovered ? Qt.alpha(Theme.danger, 0.15) : Theme.surfacePressed
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: clearHover.hovered ? Theme.danger : Theme.textSecondary
                }
                HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.deadlineIso = "" }
            }

            Text {
                text: "▾"
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
            }
        }

        HoverHandler { id: fieldHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: picker.openFor(root.deadlineIso) }
    }

    DeadlinePicker {
        id: picker
        x: 0
        y: root.height + 4
        onPicked: function(iso) { root.deadlineIso = iso }
    }
}
