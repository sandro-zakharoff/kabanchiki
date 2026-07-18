pragma Singleton
import QtQuick

// Kabanchiki brand palette (derived from the app icon):
// #766D78 #8C818F #F7F3F1 #CDB1B1 #A29AA5
QtObject {
    readonly property color bg: "#F7F3F1"
    readonly property color surface: "#FFFFFF"
    readonly property color surfaceAlt: "#F1ECEA"
    readonly property color surfacePressed: "#E7E0DE"
    readonly property color border: "#E4DCD9"
    readonly property color textPrimary: "#38333B"
    readonly property color textSecondary: "#A29AA5"

    readonly property color accent: "#766D78"
    readonly property color accentSoft: "#CDB1B1"
    readonly property color accentDark: "#4A434E"
    readonly property color danger: "#C96A5F"
    readonly property color warning: "#D99A5B"
    readonly property color success: "#6FA287"
    readonly property color info: "#8598B5"

    readonly property int radiusSm: 10
    readonly property int radiusMd: 16
    readonly property int radiusLg: 22

    readonly property int spacingXs: 4
    readonly property int spacingSm: 8
    readonly property int spacingMd: 16
    readonly property int spacingLg: 24
    readonly property int spacingXl: 32


    readonly property int marginXs: 4
    readonly property int marginSm: 8
    readonly property int marginMd: 16
    readonly property int marginLg: 24
    readonly property int marginXl: 32

    readonly property string fontFamily: "Segoe UI"
    readonly property int fontSizeXs: 11
    readonly property int fontSizeSm: 12
    readonly property int fontSizeMd: 14
    readonly property int fontSizeLg: 17
    readonly property int fontSizeXl: 22
    readonly property int fontSizeXxl: 28

    readonly property int animFast: 120
    readonly property int animMed: 220
    readonly property int animSlow: 360
}
