import QtQuick
import "."

// Um ícone do Material Design Icons, pelo nome.
Text {
    property string name
    property int size: 16
    font.family: T.iconFamily
    font.pixelSize: size
    text: String.fromCodePoint(T.glyph[name] || T.glyph["alert-circle"])
    color: T.moon
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
