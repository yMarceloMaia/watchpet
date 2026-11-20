import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

// Superfície de um grupo de conteúdo: cantos de 8, borda de 1 px, respiro de 16.
Rectangle {
    id: panel
    default property alias content: body.data
    property string title
    property string subtitle
    property alias actions: actionRow.data
    property int padding: T.s16

    color: T.dusk
    radius: T.r8
    border.width: 1
    border.color: T.seam
    implicitHeight: body.implicitHeight + padding * 2
    implicitWidth: 320

    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: panel.padding }
        spacing: T.s8

        RowLayout {
            visible: panel.title !== ""
            Layout.fillWidth: true
            Layout.bottomMargin: T.s4
            spacing: T.s8
            ColumnLayout {
                spacing: T.s2
                Layout.fillWidth: true
                Label { text: panel.title; font.pixelSize: T.strong; font.weight: Font.DemiBold; color: T.moon }
                Label { visible: panel.subtitle !== ""; text: panel.subtitle; font.pixelSize: T.caption; color: T.fog; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
            RowLayout { id: actionRow; spacing: T.s4 }
        }
    }
}
