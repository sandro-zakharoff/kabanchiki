import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    // Consistent titled card used for every settings group.
    component Section: Card {
        id: sec
        Layout.fillWidth: true
        property string heading: ""
        property string caption: ""
        default property alias content: contentCol.data
        implicitHeight: outerCol.implicitHeight + Theme.spacingLg * 2

        ColumnLayout {
            id: outerCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingMd

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: sec.heading
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                }
                Text {
                    visible: sec.caption.length > 0
                    text: sec.caption
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            ColumnLayout {
                id: contentCol
                Layout.fillWidth: true
                spacing: Theme.spacingMd
            }
        }
    }

    // Label above an input, consistent across the page.
    component Labeled: ColumnLayout {
        property string label: ""
        default property alias inner: box.data
        Layout.fillWidth: true
        spacing: Theme.spacingXs
        Text { text: parent.label; font.pixelSize: Theme.fontSizeSm; color: Theme.textSecondary }
        ColumnLayout { id: box; Layout.fillWidth: true; spacing: 0 }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: outer.implicitHeight + Theme.spacingXl * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: outer
            x: Math.max(Theme.spacingLg, (parent.width - width) / 2)
            y: Theme.spacingXl
            width: Math.min(parent.width - Theme.spacingLg * 2, 760)
            spacing: Theme.spacingLg

            Text {
                text: qsTr("Settings")
                font.pixelSize: Theme.fontSizeXxl
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            // ---------------------------------------------------- Connection
            Section {
                heading: qsTr("Connection")
                caption: qsTr("The Supabase project that holds your family's data. Everyone in the family connects to the same one.")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: backend.connected ? Theme.success : Theme.warning
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: qsTr("Project URL")
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textSecondary
                        }
                        Text {
                            text: backend.supabaseUrl || "—"
                            font.pixelSize: Theme.fontSizeMd
                            font.weight: Font.DemiBold
                            color: Theme.textPrimary
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }
                    AppButton {
                        visible: backend.isOwner
                        small: true
                        variant: "secondary"
                        text: qsTr("Change project…")
                        onClicked: changeConnectionDialog.open()
                    }
                }
            }

            // ---------------------------------------------------- Account
            Section {
                heading: qsTr("Account")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd
                    Avatar {
                        name: backend.parentEmail
                        color: Theme.accent
                        size: 44
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: qsTr("Signed in as")
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textSecondary
                        }
                        Text {
                            text: backend.parentEmail
                            font.pixelSize: Theme.fontSizeMd
                            font.weight: Font.DemiBold
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    AppButton { variant: "secondary"; small: true; text: qsTr("Change password…"); onClicked: ownPasswordDialog.open() }
                    AppButton { variant: "danger"; small: true; text: qsTr("Sign out"); onClicked: backend.logout() }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.7 }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs
                    Text {
                        text: qsTr("Owners")
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: Theme.textPrimary
                    }
                    Text {
                        text: qsTr("Owners have full access from the desktop and Telegram.")
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Repeater {
                    model: backend.owners
                    delegate: RowLayout {
                        id: ownerRow
                        required property var modelData
                        readonly property bool isSelf: modelData.email === backend.parentEmail
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        opacity: modelData.disabled ? 0.55 : 1
                        Avatar { name: modelData.display_name || modelData.email; color: Theme.accentSoft; size: 32 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: (modelData.display_name || modelData.email || "—")
                                    + (ownerRow.isSelf ? qsTr(" (you)") : "")
                                font.pixelSize: Theme.fontSizeMd
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: (modelData.email && modelData.display_name) || (modelData.phone || "").length > 0
                                text: (modelData.email || "")
                                    + ((modelData.phone || "").length > 0 ? " · " + modelData.phone : "")
                                font.pixelSize: Theme.fontSizeXs
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: (modelData.note || "").length > 0
                                text: modelData.note || ""
                                font.pixelSize: Theme.fontSizeXs
                                color: Theme.textSecondary
                                font.italic: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        Chip { visible: modelData.disabled === true; text: qsTr("disabled"); chipColor: Theme.danger }
                        Chip { visible: modelData.is_owner && !modelData.disabled; text: qsTr("owner"); chipColor: Theme.accent }
                        AppButton {
                            small: true
                            variant: "secondary"
                            text: qsTr("Edit")
                            // Owners edit anyone; a non-owner could edit only themselves.
                            visible: backend.isOwner || ownerRow.isSelf
                            onClicked: ownerEditDialog.openFor(modelData)
                        }
                        AppButton {
                            visible: backend.isOwner && !ownerRow.isSelf
                            small: true
                            variant: modelData.disabled ? "secondary" : "ghost"
                            text: modelData.disabled ? qsTr("Enable") : qsTr("Disable")
                            onClicked: {
                                if (modelData.disabled) {
                                    backend.setOwnerDisabled(modelData.id, false)
                                } else {
                                    confirmRef.openWith(
                                        qsTr("Disable owner"),
                                        qsTr("“%1” will not be able to sign in from the desktop or Telegram until enabled again. Disable?")
                                            .arg(modelData.display_name || modelData.email),
                                        function() { backend.setOwnerDisabled(modelData.id, true) }, true)
                                }
                            }
                        }
                        AppButton {
                            visible: backend.isOwner && !ownerRow.isSelf
                            small: true
                            variant: "ghost"
                            text: qsTr("Remove")
                            onClicked: confirmRef.openWith(
                                qsTr("Remove owner"),
                                qsTr("“%1” will lose access to the family. Continue?").arg(modelData.display_name || modelData.email),
                                function() { backend.deleteOwner(modelData.id) }, true)
                        }
                    }
                }

                AppButton {
                    variant: "secondary"
                    text: qsTr("+ Add owner")
                    onClicked: addOwnerDialog.open()
                }
            }

            // ---------------------------------------------------- Balance
            Section {
                id: balanceSection
                heading: qsTr("Balance")
                caption: qsTr("Global money rules for every assignee. Only owners can change them.")

                function seed() {
                    minField.text = String(backend.minWithdrawal)
                    autoField.text = String(backend.autoApproveBelow)
                    enabledBox.checked = backend.withdrawalsEnabled
                    receiptBox.checked = backend.requireReceiptForCard
                }
                Component.onCompleted: seed()
                Connections { target: backend; function onBalanceSettingsChanged() { balanceSection.seed() } }

                readonly property bool editable: backend.isOwner

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd
                    Labeled {
                        label: qsTr("Minimum withdrawal, ₴")
                        Layout.preferredWidth: 200
                        AppTextField {
                            id: minField
                            Layout.fillWidth: true
                            enabled: balanceSection.editable
                            placeholderText: "0.00"
                            validator: DoubleValidator { bottom: 0; decimals: 2; notation: DoubleValidator.StandardNotation }
                        }
                    }
                    Labeled {
                        label: qsTr("Auto-approve below, ₴ (0 = off)")
                        Layout.preferredWidth: 200
                        AppTextField {
                            id: autoField
                            Layout.fillWidth: true
                            enabled: balanceSection.editable
                            placeholderText: "0.00"
                            validator: DoubleValidator { bottom: 0; decimals: 2; notation: DoubleValidator.StandardNotation }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                AppCheckBox {
                    id: enabledBox
                    Layout.fillWidth: true
                    enabled: balanceSection.editable
                    text: qsTr("Allow assignees to request withdrawals")
                }
                AppCheckBox {
                    id: receiptBox
                    Layout.fillWidth: true
                    enabled: balanceSection.editable
                    text: qsTr("Require a receipt for card payouts")
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    AppButton {
                        text: qsTr("Save")
                        enabled: balanceSection.editable
                        onClicked: backend.setBalanceSettings(
                            parseFloat(minField.text.replace(",", ".")) || 0,
                            enabledBox.checked,
                            parseFloat(autoField.text.replace(",", ".")) || 0,
                            receiptBox.checked)
                    }
                }
            }

            // ---------------------------------------------------- Telegram
            Section {
                heading: qsTr("Telegram")
                caption: qsTr("Manage the family from a Telegram Mini App with the same owner accounts. Link your own Telegram below.")

                // One connection indicator for the whole bot setup.
                RowLayout {
                    visible: backend.isOwner
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    readonly property bool ready: backend.telegramBotConfigured
                        && backend.telegramBotUsername.length > 0
                        && backend.telegramMiniappUrl.length > 0
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: parent.ready ? Theme.success : Theme.warning
                    }
                    Text {
                        text: parent.ready
                            ? qsTr("Bot is configured and ready")
                            : qsTr("Fill in and save the bot settings below")
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd
                    visible: backend.isOwner

                    Labeled {
                        label: qsTr("Bot username")
                        AppTextField {
                            id: tgBot
                            Layout.fillWidth: true
                            placeholderText: "my_family_bot"
                            text: backend.telegramBotUsername
                        }
                    }
                    Labeled {
                        label: qsTr("Mini App URL")
                        AppTextField {
                            id: tgUrl
                            Layout.fillWidth: true
                            placeholderText: "https://user.github.io/kabanchiki/"
                            text: backend.telegramMiniappUrl
                        }
                        Text {
                            visible: tgUrl.text.trim().length > 0 && !tgUrl.text.trim().startsWith("https://")
                            text: qsTr("Telegram requires an https:// address")
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.danger
                        }
                    }
                    Labeled {
                        label: qsTr("Bot token (from @BotFather)")
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm
                            AppTextField {
                                id: tgToken
                                Layout.fillWidth: true
                                echoMode: TextInput.Password
                                placeholderText: backend.telegramBotConfigured
                                    ? qsTr("Token saved — paste a new one to replace")
                                    : qsTr("Paste the token, e.g. 1234567890:AA…")
                            }
                            AppButton {
                                small: true
                                variant: "ghost"
                                visible: backend.telegramBotConfigured
                                text: qsTr("Remove token")
                                onClicked: confirmRef.openWith(
                                    qsTr("Remove bot token"),
                                    qsTr("The Mini App will stop signing users in until a new token is saved. Remove?"),
                                    function() { backend.clearBotToken() }, true)
                            }
                        }
                        Text {
                            readonly property string t: tgToken.text.trim()
                            visible: t.length > 0 && !/^\d+:[A-Za-z0-9_-]{30,}$/.test(t)
                            text: qsTr("This does not look like a bot token (expected 1234567890:AA…)")
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.danger
                        }
                    }

                    // The only save action for the section.
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        AppButton {
                            text: qsTr("Save")
                            enabled: tgBot.text.trim().length > 0
                                && tgUrl.text.trim().startsWith("https://")
                                && (tgToken.text.trim().length === 0
                                    || /^\d+:[A-Za-z0-9_-]{30,}$/.test(tgToken.text.trim()))
                            onClicked: {
                                backend.saveTelegramSettings(tgBot.text, tgUrl.text, tgToken.text)
                                tgToken.text = ""
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.7 }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: backend.telegramLinked ? Theme.success : Theme.textSecondary
                    }
                    Text {
                        text: backend.telegramLinked ? qsTr("Your Telegram is linked") : qsTr("Your Telegram is not linked")
                        font.pixelSize: Theme.fontSizeMd
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                    }
                    AppButton {
                        visible: !backend.telegramLinked
                        text: qsTr("Link my Telegram")
                        onClicked: backend.startTelegramLink()
                    }
                    AppButton {
                        visible: backend.telegramLinked
                        variant: "danger"
                        text: qsTr("Unlink")
                        onClicked: confirmRef.openWith(
                            qsTr("Unlink Telegram"),
                            qsTr("You will lose access to the Mini App until you link again. Continue?"),
                            function() { backend.unlinkTelegram() }, true)
                    }
                }
            }

            // ---------------------------------------------------- Google Drive
            Section {
                heading: qsTr("Google Drive")
                caption: qsTr("Store the family's photos on your own Google Drive instead of Supabase. Create an OAuth Client ID (Desktop app) in Google Cloud Console, then paste it below.")

                // Connection status.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: backend.gdriveConnected ? Theme.success : Theme.textSecondary
                        Behavior on color { ColorAnimation { duration: Theme.animMed } }
                    }
                    Text {
                        text: backend.gdriveConnected
                            ? qsTr("Connected: %1").arg(backend.gdriveEmail)
                            : qsTr("Not connected")
                        font.pixelSize: Theme.fontSizeMd
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    AppButton {
                        visible: backend.gdriveConnected
                        small: true
                        variant: "secondary"
                        text: qsTr("Check connection")
                        onClicked: backend.testGdrive()
                    }
                    AppButton {
                        visible: backend.gdriveConnected
                        small: true
                        variant: "danger"
                        text: qsTr("Disconnect")
                        onClicked: confirmRef.openWith(
                            qsTr("Disconnect Google Drive"),
                            qsTr("New photos will go to Supabase again. Files already on Drive stay visible. Continue?"),
                            function() { backend.disconnectGdrive() }, true)
                    }
                }

                ColumnLayout {
                    visible: backend.isOwner
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd

                    Labeled {
                        label: qsTr("Client ID")
                        AppTextField {
                            id: gdriveClientId
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. 1234…apps.googleusercontent.com")
                            text: backend.gdriveClientId
                        }
                    }
                    Labeled {
                        label: qsTr("Client Secret")
                        AppTextField {
                            id: gdriveClientSecret
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: backend.gdriveConnected
                                ? qsTr("Saved — paste a new one to replace")
                                : qsTr("GOCSPX-…")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        AppButton {
                            text: backend.gdriveConnected ? qsTr("Reconnect…") : qsTr("Connect…")
                            enabled: gdriveClientId.text.trim().length > 0
                            onClicked: backend.connectGdrive(gdriveClientId.text, gdriveClientSecret.text)
                        }
                        Text {
                            text: qsTr("A browser window will open for Google sign-in")
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.textSecondary
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; opacity: 0.7 }

                    // Where NEW photos are stored.
                    Labeled {
                        label: qsTr("Store new photos in")
                        RowLayout {
                            spacing: Theme.spacingSm
                            Repeater {
                                model: [
                                    { value: "supabase", label: qsTr("Supabase (built-in)") },
                                    { value: "drive", label: qsTr("Google Drive") }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool active: backend.storageBackend === modelData.value
                                    width: segLabel.implicitWidth + 32
                                    height: 36
                                    radius: Theme.radiusSm
                                    color: active ? Theme.accent : Theme.surfaceAlt
                                    border.width: 1
                                    border.color: active ? Theme.accent : Theme.border
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                    opacity: modelData.value === "drive" && !backend.gdriveConnected ? 0.55 : 1
                                    Text {
                                        id: segLabel
                                        anchors.centerIn: parent
                                        text: parent.modelData.label
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: Font.DemiBold
                                        color: parent.active ? "#FFFFFF" : Theme.textPrimary
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: backend.setStorageBackend(parent.modelData.value) }
                                }
                            }
                        }
                    }
                }
            }

            // ---------------------------------------------------- Language
            Section {
                heading: qsTr("Language")

                AppComboBox {
                    Layout.preferredWidth: 280
                    textRole: "label"
                    model: [
                        { label: "Українська", code: "uk" },
                        { label: "English", code: "en" }
                    ]
                    currentIndex: backend.language === "en" ? 1 : 0
                    onActivated: backend.setLanguage(model[currentIndex].code)
                }
            }

            // ---------------------------------------------------- Android updates
            Section {
                heading: qsTr("Android app updates")
                caption: qsTr("Publish a new APK — assignees get a push and an in-app “Update” banner. No Play Market needed.")

                AppButton {
                    text: qsTr("Publish an update…")
                    variant: "secondary"
                    onClicked: publishUpdateDialog.openDialog()
                }
            }

            // ---------------------------------------------------- About
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingXs
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    Image {
                        source: backend.appIconUrl
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                        fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
                    }
                    Text {
                        text: "Kabanchiki " + backend.appVersion()
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Font.DemiBold
                        color: Theme.textSecondary
                    }
                    Text {
                        text: "· " + qsTr("Family task & reward system")
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.textSecondary
                    }
                    Item { Layout.fillWidth: true }
                }
                Text {
                    text: "© %1 Zakharoff · Oleksandr Zakharov".arg(new Date().getFullYear())
                    font.pixelSize: Theme.fontSizeXs
                    color: Theme.textSecondary
                    Layout.leftMargin: 30
                }
            }

            Item { Layout.preferredHeight: Theme.spacingLg }
        }
    }

    PublishUpdateDialog { id: publishUpdateDialog }
    OwnerEditDialog { id: ownerEditDialog }

    AppDialog {
        id: changeConnectionDialog
        title: qsTr("Change project")
        onOpened: { connUrl.text = backend.supabaseUrl; connKey.text = "" }
        contentItem: ColumnLayout {
            implicitWidth: 440
            spacing: Theme.spacingMd
            Text {
                text: qsTr("Point the app at a different Supabase project. The connection is tested before it is saved, and you will be signed out to sign in on the new project.")
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            AppTextField { id: connUrl; Layout.fillWidth: true; placeholderText: "https://your-project.supabase.co" }
            AppTextField { id: connKey; Layout.fillWidth: true; placeholderText: qsTr("Anon (publishable) key") }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: changeConnectionDialog.close() }
                AppButton {
                    text: qsTr("Test & save")
                    enabled: connUrl.text.trim().startsWith("https://") && connKey.text.trim().length > 0
                    onClicked: { backend.changeConnection(connUrl.text, connKey.text); changeConnectionDialog.close() }
                }
            }
        }
    }

    Connections {
        target: backend
        function onTelegramLinkReady(code, link) {
            tgLinkField.text = link
            telegramLinkDialog.open()
        }
    }

    AppDialog {
        id: addOwnerDialog
        title: qsTr("Add owner")
        acceptAction: function() {
            if (!(ownerEmail.text.indexOf("@") > 0 && ownerPass.text.length >= 6)) return
            backend.createOwner(ownerEmail.text, ownerPass.text, ownerName.text)
            addOwnerDialog.close()
        }
        onOpened: { ownerName.text = ""; ownerEmail.text = ""; ownerPass.text = "" }
        contentItem: ColumnLayout {
            implicitWidth: 380
            spacing: Theme.spacingMd
            Text { text: qsTr("Give another owner full access. They sign in with this email and password."); font.pixelSize: Theme.fontSizeSm; color: Theme.textSecondary; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            AppTextField { id: ownerName; Layout.fillWidth: true; placeholderText: qsTr("Name") }
            AppTextField { id: ownerEmail; Layout.fillWidth: true; placeholderText: qsTr("Email") }
            AppTextField { id: ownerPass; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: qsTr("Password (min. 6)") }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: addOwnerDialog.close() }
                AppButton {
                    text: qsTr("Add")
                    enabled: ownerEmail.text.indexOf("@") > 0 && ownerPass.text.length >= 6
                    onClicked: { backend.createOwner(ownerEmail.text, ownerPass.text, ownerName.text); addOwnerDialog.close() }
                }
            }
        }
    }

    AppDialog {
        id: ownPasswordDialog
        title: qsTr("Change password")
        acceptAction: function() {
            if (newPass.text.length < 6) return
            backend.changeOwnPassword(newPass.text)
            ownPasswordDialog.close()
        }
        onOpened: newPass.text = ""
        contentItem: ColumnLayout {
            implicitWidth: 360
            spacing: Theme.spacingMd
            AppTextField { id: newPass; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: qsTr("New password (min. 6)") }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                AppButton { text: qsTr("Cancel"); variant: "ghost"; onClicked: ownPasswordDialog.close() }
                AppButton {
                    text: qsTr("Save")
                    enabled: newPass.text.length >= 6
                    onClicked: { backend.changeOwnPassword(newPass.text); ownPasswordDialog.close() }
                }
            }
        }
    }

    AppDialog {
        id: telegramLinkDialog
        title: qsTr("Link Telegram")
        contentItem: ColumnLayout {
            implicitWidth: 440
            spacing: Theme.spacingMd
            Text {
                text: qsTr("Open this link on the phone that has your Telegram and press Start. It links this account to the Mini App and expires in 15 minutes.")
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            AppTextField { id: tgLinkField; Layout.fillWidth: true; readOnly: true }
            RowLayout {
                Layout.fillWidth: true
                AppButton { text: qsTr("Copy link"); variant: "secondary"; onClicked: backend.copyToClipboard(tgLinkField.text) }
                Item { Layout.fillWidth: true }
                AppButton { text: qsTr("Done"); onClicked: telegramLinkDialog.close() }
            }
        }
    }
}
