import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    Rectangle { anchors.fill: parent; color: Theme.bg }

    Card {
        anchors.centerIn: parent
        width: 420
        height: contentCol.implicitHeight + Theme.spacingXl * 2

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: Theme.spacingXl
            spacing: Theme.spacingMd

            Image {
                source: backend.appIconUrl
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72
                Layout.alignment: Qt.AlignHCenter
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Text {
                text: "Kabanchiki"
                font.pixelSize: Theme.fontSizeXxl
                font.weight: Font.Bold
                color: Theme.textPrimary
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: qsTr("Sign in to your owner account")
                font.pixelSize: Theme.fontSizeMd
                color: Theme.textSecondary
                Layout.alignment: Qt.AlignHCenter
            }

            Item { height: Theme.spacingSm }

            Text {
                text: qsTr("Email")
                font.pixelSize: Theme.fontSizeSm
                font.weight: Font.DemiBold
                color: Theme.textSecondary
            }
            AppTextField {
                id: emailField
                Layout.fillWidth: true
                placeholderText: "you@example.com"
                onAccepted: passwordField.forceActiveFocus()
            }

            Text {
                text: qsTr("Password")
                font.pixelSize: Theme.fontSizeSm
                font.weight: Font.DemiBold
                color: Theme.textSecondary
            }
            AppTextField {
                id: passwordField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: qsTr("password")
                onAccepted: if (emailField.text.length > 0 && text.length > 0) backend.login(emailField.text, text)
            }

            Item { height: Theme.spacingSm }

            AppButton {
                Layout.fillWidth: true
                text: backend.busy ? qsTr("Signing in…") : qsTr("Sign in")
                enabled: !backend.busy && emailField.text.length > 0 && passwordField.text.length > 0
                onClicked: backend.login(emailField.text, passwordField.text)
            }
        }
    }
}
