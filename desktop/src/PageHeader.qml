import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

// Título da página, uma linha que explica o que se faz nela e as ações à direita.
RowLayout {
    property string title
    property string subtitle
    default property alias actions: actionRow.data
    Layout.fillWidth: true
    spacing: T.s16
    ColumnLayout {
        spacing: T.s4
        Layout.fillWidth: true
        Label { text: parent.parent.title; font.pixelSize: T.display; font.weight: Font.Bold; color: T.moon }
        Label { visible: text !== ""; text: parent.parent.subtitle; color: T.fog; font.pixelSize: T.body; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }
    RowLayout { id: actionRow; spacing: T.s8; Layout.alignment: Qt.AlignBottom }
}
