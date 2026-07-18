import QtQuick
import QtQuick.Controls.Basic

ApplicationWindow {
    id: window
    width: 1920
    height: 1080
    minimumWidth: 1080
    minimumHeight: 680
    visible: true
    title: "Kabanchiki"
    color: Theme.bg

    font.family: Theme.fontFamily

    Component.onCompleted: backend.attachWindow(window)

    onClosing: function(close) {
        if (!backend.allowQuit) {
            close.accepted = false
            window.hide()
            backend.notifyMinimizedToTray()
        }
    }

    Loader {
        anchors.fill: parent
        // First run has no Supabase project yet → wizard; then sign-in; then app.
        sourceComponent: !backend.connectionReady ? setupComponent
            : backend.configured ? shellComponent
            : connectComponent
    }

    Component {
        id: setupComponent
        ConnectionSetupScreen { }
    }

    Component {
        id: shellComponent
        Shell { }
    }

    Component {
        id: connectComponent
        ConnectScreen { }
    }

    Toast {
        anchors.fill: parent
    }
}
