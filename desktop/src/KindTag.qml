import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

// Marca de um tipo de visita (caixa, comida, água): quadradinho na cor do tipo, número e nome.
RowLayout {
    property string kind
    property var count: undefined     // sem número: só a marca e o nome
    property bool showName: true
    spacing: T.s4
    Rectangle { width: T.s8; height: T.s8; radius: T.r2; color: T.kindColor(parent.kind) }
    Label {
        visible: parent.count !== undefined
        text: parent.count === undefined ? "" : String(parent.count)
        font.pixelSize: T.strong; font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        color: T.moon
    }
    Label { visible: parent.showName; text: T.kindShort[parent.kind] || parent.kind; font.pixelSize: T.caption; color: T.fog }
}
