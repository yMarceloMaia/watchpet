import QtQuick
import QtQuick.Controls
import "."

// Botão só com ícone, para ações secundárias; a dica aparece no hover e no foco.
ToolButton {
    id: b
    property string icon_: "close"
    property string tip
    property color tint: T.moon
    property bool selected: false
    implicitWidth: 32; implicitHeight: 32
    padding: T.s4
    contentItem: Icon { name: b.icon_; size: 18; color: !b.enabled ? T.fog : b.selected ? theme.accent : b.tint; opacity: b.enabled ? 1 : .4 }
    background: Rectangle { radius: T.r4; color: b.down ? T.seam : b.selected || b.hovered || b.visualFocus ? T.haze : "transparent"
        border.width: b.visualFocus || b.selected ? 1 : 0; border.color: b.visualFocus ? T.fog : T.seam }
    ToolTip.visible: hovered && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 400
    Accessible.name: tip
}
