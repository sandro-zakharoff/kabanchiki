import QtQuick
import QtQuick.Layouts

// Difficulty as 5 filled segments + a readable label, instead of a bare digit.
Rectangle {
    id: root
    property int level: 1 // 1..5
    property bool showLabel: true

    readonly property var levelColors: ["#6FA287", "#8598B5", "#D99A5B", "#CE8158", "#C96A5F"]
    readonly property color levelColor: levelColors[Math.max(0, Math.min(4, level - 1))]
    readonly property var levelNames: [
        qsTr("Very easy"), qsTr("Easy"), qsTr("Medium"), qsTr("Hard"), qsTr("Very hard")
    ]

    implicitHeight: 24
    implicitWidth: row.implicitWidth + 20
    radius: 12
    color: Qt.alpha(levelColor, 0.13)

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Row {
            spacing: 2
            Repeater {
                model: 5
                delegate: Rectangle {
                    required property int index
                    width: 5
                    height: 10
                    radius: 2
                    color: index < root.level ? root.levelColor : Qt.alpha(root.levelColor, 0.25)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }
            }
        }

        Text {
            visible: root.showLabel
            text: root.levelNames[Math.max(0, Math.min(4, root.level - 1))]
            font.pixelSize: Theme.fontSizeXs
            font.weight: Font.DemiBold
            color: root.levelColor
        }
    }
}
