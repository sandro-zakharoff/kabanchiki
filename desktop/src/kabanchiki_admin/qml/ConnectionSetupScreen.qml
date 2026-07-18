import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// First-run wizard: point the app at the family's own Supabase project.
// Nothing is saved until the connection actually answers, so a wrong value
// never leaves the user stuck. The app never ships with someone else's project.
Item {
    id: root

    Rectangle { anchors.fill: parent; color: Theme.bg }

    Flickable {
        anchors.fill: parent
        contentHeight: card.height + Theme.spacingXl * 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Card {
            id: card
            x: Math.max(Theme.spacingLg, (parent.width - width) / 2)
            y: Theme.spacingXl
            width: Math.min(parent.width - Theme.spacingLg * 2, 520)
            height: contentCol.implicitHeight + Theme.spacingXl * 2

            ColumnLayout {
                id: contentCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingXl
                spacing: Theme.spacingMd

                Image {
                    source: backend.appIconUrl
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    Layout.alignment: Qt.AlignHCenter
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                Text {
                    text: qsTr("Connect your Supabase")
                    font.pixelSize: Theme.fontSizeXxl
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: qsTr("Kabanchiki stores your family's data in your own Supabase project. "
                        + "Paste its address and publishable (anon) key to get started.")
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }

                Item { height: Theme.spacingXs }

                Text {
                    text: qsTr("Project URL")
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    color: Theme.textSecondary
                }
                AppTextField {
                    id: urlField
                    Layout.fillWidth: true
                    placeholderText: "https://your-project.supabase.co"
                    // Seed a URL we may already know (e.g. partial saved config).
                    Component.onCompleted: text = backend.supabaseUrl
                    onAccepted: keyField.forceActiveFocus()
                }
                Text {
                    readonly property string t: urlField.text.trim()
                    visible: t.length > 0 && !t.startsWith("https://")
                    text: qsTr("The address must start with https://")
                    font.pixelSize: Theme.fontSizeXs
                    color: Theme.danger
                }

                Text {
                    text: qsTr("Anon (publishable) key")
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    color: Theme.textSecondary
                }
                AppTextField {
                    id: keyField
                    Layout.fillWidth: true
                    placeholderText: "eyJhbGciOi…"
                }
                Text {
                    text: qsTr("Found in Supabase → Project Settings → API. It is safe to ship in a client — your data is protected by row-level security.")
                    font.pixelSize: Theme.fontSizeXs
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Item { height: Theme.spacingSm }

                AppButton {
                    Layout.fillWidth: true
                    text: backend.busy ? qsTr("Checking…") : qsTr("Test connection & continue")
                    enabled: !backend.busy
                        && urlField.text.trim().startsWith("https://")
                        && keyField.text.trim().length > 0
                    onClicked: backend.saveConnection(urlField.text, keyField.text)
                }
            }
        }
    }
}
