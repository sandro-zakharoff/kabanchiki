import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Custom deadline picker: month calendar + hour/minute wheels + presets and
// an explicit "No deadline" action. Emits picked(iso) — "" means no deadline.
Popup {
    id: root
    modal: true
    padding: 18
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    signal picked(string iso)

    property date selectedDay: new Date(NaN)
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()

    readonly property var monthNames: [
        qsTr("January"), qsTr("February"), qsTr("March"), qsTr("April"),
        qsTr("May"), qsTr("June"), qsTr("July"), qsTr("August"),
        qsTr("September"), qsTr("October"), qsTr("November"), qsTr("December")
    ]
    readonly property var dowNames: [qsTr("Mo"), qsTr("Tu"), qsTr("We"), qsTr("Th"),
                                     qsTr("Fr"), qsTr("Sa"), qsTr("Su")]

    function openFor(iso) {
        var d = iso && iso.length > 0 ? new Date(iso) : null
        var base = d || new Date()
        viewYear = base.getFullYear()
        viewMonth = base.getMonth()
        selectedDay = d ? new Date(d.getFullYear(), d.getMonth(), d.getDate()) : new Date(NaN)
        hourWheel.currentIndex = d ? d.getHours() : 18
        minuteWheel.currentIndex = d ? Math.round(d.getMinutes() / 5) % 12 : 0
        open()
    }

    function daysGrid() {
        // Monday-first cells; leading blanks are nulls.
        var first = new Date(viewYear, viewMonth, 1)
        var lead = (first.getDay() + 6) % 7
        var count = new Date(viewYear, viewMonth + 1, 0).getDate()
        var cells = []
        for (var i = 0; i < lead; i++) cells.push(0)
        for (var day = 1; day <= count; day++) cells.push(day)
        return cells
    }

    function finish(dateOrNull) {
        root.close()
        root.picked(dateOrNull ? dateOrNull.toISOString() : "")
    }

    function commit() {
        var today = new Date(); today.setHours(0, 0, 0, 0)
        var base = isNaN(selectedDay.getTime()) ? today : selectedDay
        var result = new Date(base)
        result.setHours(hourWheel.currentIndex, minuteWheel.currentIndex * 5, 0, 0)
        finish(result)
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMed; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.animMed; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.animFast } }

    background: Rectangle {
        color: Theme.surface
        radius: Theme.radiusMd
        border.width: 1
        border.color: Theme.border
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingSm

        // ---- month header
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.monthNames[root.viewMonth] + " " + root.viewYear
                font.pixelSize: Theme.fontSizeMd
                font.weight: Font.Bold
                color: Theme.textPrimary
                Layout.fillWidth: true
            }
            Repeater {
                model: [{ t: "‹", d: -1 }, { t: "›", d: 1 }]
                delegate: Rectangle {
                    required property var modelData
                    width: 30; height: 30; radius: 8
                    color: navHover.hovered ? Theme.surfacePressed : Theme.surfaceAlt
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.t
                        font.pixelSize: 16; color: Theme.textPrimary
                    }
                    HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            var m = root.viewMonth + parent.modelData.d
                            if (m < 0) { root.viewMonth = 11; root.viewYear-- }
                            else if (m > 11) { root.viewMonth = 0; root.viewYear++ }
                            else root.viewMonth = m
                        }
                    }
                }
            }
        }

        // ---- calendar grid
        GridLayout {
            columns: 7
            columnSpacing: 2
            rowSpacing: 2
            Layout.fillWidth: true

            Repeater {
                model: root.dowNames
                delegate: Text {
                    required property string modelData
                    text: modelData
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Font.Bold
                    color: Theme.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    Layout.preferredWidth: 38
                }
            }

            Repeater {
                model: root.daysGrid()
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool blank: modelData === 0
                    readonly property date cellDate: blank
                        ? new Date(NaN) : new Date(root.viewYear, root.viewMonth, modelData)
                    readonly property bool isPast: {
                        if (blank) return false
                        var today = new Date(); today.setHours(0, 0, 0, 0)
                        return cellDate < today
                    }
                    readonly property bool isToday: {
                        if (blank) return false
                        var t = new Date()
                        return cellDate.getFullYear() === t.getFullYear()
                            && cellDate.getMonth() === t.getMonth()
                            && cellDate.getDate() === t.getDate()
                    }
                    readonly property bool isSelected: !blank && !isNaN(root.selectedDay.getTime())
                        && cellDate.getTime() === root.selectedDay.getTime()

                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 34
                    radius: 8
                    color: isSelected ? Theme.accent
                         : (dayHover.hovered && !blank && !isPast ? Theme.surfaceAlt : Qt.alpha(Theme.surfaceAlt, 0))
                    border.width: isToday && !isSelected ? 1 : 0
                    border.color: Qt.alpha(Theme.accent, 0.55)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: parent.blank ? "" : parent.modelData
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: parent.isSelected || parent.isToday ? Font.Bold : Font.Normal
                        color: parent.isSelected ? "#FFFFFF"
                             : parent.isPast ? Qt.alpha(Theme.textSecondary, 0.45)
                             : parent.isToday ? Theme.accent : Theme.textPrimary
                    }
                    HoverHandler {
                        id: dayHover
                        enabled: !parent.blank && !parent.isPast
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        enabled: !parent.blank && !parent.isPast
                        onTapped: root.selectedDay = parent.cellDate
                    }
                }
            }
        }

        // ---- time wheels
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.6 }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 2

            component TimeWheel: Tumbler {
                id: wheel
                visibleItemCount: 3
                implicitWidth: 64
                implicitHeight: 96
                wrap: true
                delegate: Text {
                    required property var modelData
                    required property int index
                    text: (modelData < 10 ? "0" : "") + modelData
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Math.abs(Tumbler.displacement) < 0.5 ? Font.Bold : Font.Normal
                    color: Math.abs(Tumbler.displacement) < 0.5
                        ? Theme.textPrimary
                        : Qt.alpha(Theme.textSecondary, 1 - Math.abs(Tumbler.displacement) * 0.35)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: 1.0 - Math.abs(Tumbler.displacement) / (wheel.visibleItemCount / 1.4)
                }
                background: Rectangle {
                    radius: Theme.radiusSm
                    color: Theme.surfaceAlt
                }
            }

            TimeWheel {
                id: hourWheel
                model: 24
            }
            Text {
                text: ":"
                font.pixelSize: Theme.fontSizeLg
                font.weight: Font.Bold
                color: Theme.textPrimary
            }
            TimeWheel {
                id: minuteWheel
                model: 12 // ×5 minutes
                delegate: Text {
                    required property var modelData
                    required property int index
                    readonly property int minutes: modelData * 5
                    text: (minutes < 10 ? "0" : "") + minutes
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Math.abs(Tumbler.displacement) < 0.5 ? Font.Bold : Font.Normal
                    color: Math.abs(Tumbler.displacement) < 0.5
                        ? Theme.textPrimary
                        : Qt.alpha(Theme.textSecondary, 1 - Math.abs(Tumbler.displacement) * 0.35)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: 1.0 - Math.abs(Tumbler.displacement) / (minuteWheel.visibleItemCount / 1.4)
                }
            }
        }

        // ---- presets
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            AppButton {
                small: true; variant: "ghost"; Layout.fillWidth: true
                text: qsTr("Today 18:00")
                onClicked: { var d = new Date(); d.setHours(18, 0, 0, 0); root.finish(d) }
            }
            AppButton {
                small: true; variant: "ghost"; Layout.fillWidth: true
                text: qsTr("Tomorrow 18:00")
                onClicked: {
                    var d = new Date(); d.setDate(d.getDate() + 1); d.setHours(18, 0, 0, 0)
                    root.finish(d)
                }
            }
            AppButton {
                small: true; variant: "ghost"; Layout.fillWidth: true
                text: qsTr("In a week")
                onClicked: {
                    var d = new Date(); d.setDate(d.getDate() + 7); d.setHours(18, 0, 0, 0)
                    root.finish(d)
                }
            }
        }

        // ---- footer
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingXs
            spacing: Theme.spacingSm
            AppButton {
                variant: "ghost"
                text: qsTr("No deadline")
                onClicked: root.finish(null)
            }
            Item { Layout.fillWidth: true }
            AppButton {
                text: qsTr("Done")
                onClicked: root.commit()
            }
        }
    }
}
