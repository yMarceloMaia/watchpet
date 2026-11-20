import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

// Botão de texto com ícone, para ações dentro de um painel. `primary` preenche com o accent.
AbstractButton {
    id: b
    property string icon_
    property color tint: T.moon
    property bool primary: false
    implicitHeight: 32
    implicitWidth: row.implicitWidth + T.s16 * (primary ? 2 : 1)
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    opacity: enabled ? 1 : .4
    contentItem: Item {
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: T.s8
            Icon { visible: b.icon_ !== ""; name: b.icon_; size: 16; color: b.primary ? theme.accentForeground : b.tint }
            Label { text: b.text; font.pixelSize: T.body; font.weight: Font.Medium; color: b.primary ? theme.accentForeground : b.tint }
        }
    }
    background: Rectangle {
        radius: T.r4
        color: b.primary ? (b.down ? Qt.darker(theme.accent, 1.2) : b.hovered ? Qt.lighter(theme.accent, 1.1) : theme.accent)
                         : (b.down ? T.seam : b.hovered ? T.haze : "transparent")
        border.width: b.visualFocus ? 2 : (b.primary ? 0 : 1)
        border.color: b.visualFocus ? T.moon : T.seam
    }
    Accessible.name: text
}
