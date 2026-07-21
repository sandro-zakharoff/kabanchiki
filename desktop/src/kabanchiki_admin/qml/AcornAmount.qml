import QtQuick
import QtQuick.Effects

// An amount of acorns: the number, then the acorn mark.
//
// The acorn replaced the ₴ symbol, and a mark that is an image cannot simply be
// glued onto the end of a formatted string the way a character could — it has to
// be laid out beside the number so it lands on the same optical line at every
// font size and weight. So every screen shows money through this one component
// instead of scattering Image tags, and the number itself arrives already
// formatted (fmt_acorns) with no unit baked in.
Row {
    id: root

    property string text: ""                       // the grouped number, e.g. "1 234"
    property int fontSize: Theme.fontSizeMd
    property int fontWeight: Font.DemiBold
    // Money reads better in tabular figures where it sits in a column.
    property string fontFamily: Theme.fontFamily
    property color color: Theme.textPrimary
    // Tint the mark to the text colour instead of leaving it in its own. Only
    // for dark fills, where the brown acorn would disappear: everywhere else the
    // coloured mark is the right one — it is the currency's identity, and its
    // two-tone cap is what keeps it readable as an acorn down to 12px, which a
    // flat silhouette does not survive.
    property bool mono: false
    // Trails the mark, e.g. "/ hour" for a rate — kept outside `text` so the
    // number and the mark stay one visual unit.
    property string suffix: ""
    property alias horizontalAlignment: label.horizontalAlignment

    spacing: Math.round(root.fontSize * 0.3)

    Text {
        id: label
        text: root.text
        font.pixelSize: root.fontSize
        font.weight: root.fontWeight
        font.family: root.fontFamily
        color: root.color
        anchors.verticalCenter: parent.verticalCenter
    }

    Item {
        // Sized off the cap height rather than the full line box, so the mark
        // optically matches the digits instead of towering over them.
        width: Math.round(root.fontSize * 1.06)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        // The acorn's visual mass sits a touch high in its own box; nudge it down
        // so it centres on the digits rather than on the line.
        anchors.verticalCenterOffset: Math.round(root.fontSize * 0.06)

        Image {
            id: mark
            anchors.fill: parent
            // Always the filled artwork, even when tinting: its alpha is the
            // acorn's true silhouette. The outline version loses its shape
            // entirely below ~20px — the cap hatching fills in and it reads as
            // a padlock — so it is never what a 12px label should show.
            source: backend.acornIconUrl
            // Vector art: sourceSize is the rasterisation size, so ask for a
            // few times the drawn size and the mark stays crisp on any DPI.
            sourceSize.width: Math.round(parent.width * 4)
            sourceSize.height: Math.round(parent.height * 4)
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: !root.mono
        }

        // Recolouring is a masking job, not a tinting one: hue filters preserve
        // luminance, so no amount of tinting turns the artwork a flat white on a
        // dark chip. Fill a rectangle with the label's colour instead and cut it
        // out with the mark's own alpha — native Qt6, exact at any colour.
        Loader {
            anchors.fill: parent
            active: root.mono
            sourceComponent: MultiEffect {
                source: ShaderEffectSource {
                    sourceItem: Rectangle { width: mark.width; height: mark.height; color: root.color }
                    hideSource: true
                }
                maskEnabled: true
                maskSource: ShaderEffectSource {
                    sourceItem: mark
                    hideSource: true
                }
            }
        }
    }

    Text {
        visible: root.suffix.length > 0
        text: root.suffix
        font.pixelSize: root.fontSize
        font.family: Theme.fontFamily
        color: root.color
        anchors.verticalCenter: parent.verticalCenter
    }
}
