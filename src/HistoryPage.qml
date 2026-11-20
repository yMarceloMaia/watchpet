import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

ListView {
    id: page
    property var app
    property bool active: false
    property string kindFilter: ""
    property string catFilter: ""
    clip: true
    spacing: T.s8
    topMargin: T.s32; bottomMargin: T.s32
    ScrollBar.vertical: ScrollBar {}

    model: backend.recent.filter(v => (!kindFilter || v.kind === kindFilter) && (!catFilter || v.cat === catFilter))

    function level(score) { return score === null || score === undefined ? "" : score >= 0.85 ? "alta" : score >= 0.75 ? "média" : "baixa" }
    function levelColor(score) { return score >= 0.85 ? T.ok : score >= 0.75 ? T.warn : T.alert }

    header: ColumnLayout {
        x: T.s32
        width: page.width - T.s64
        spacing: T.s16
        PageHeader {
            title: "Histórico"
            subtitle: "Cada visita com a foto do momento e o quanto o Catwatch tinha certeza do gato. Errou? Troque o gato."
        }
        RowLayout {
            spacing: T.s8
            Layout.bottomMargin: T.s8
            Repeater {
                model: [{ k: "", t: "Tudo" }, { k: "litter", t: "Caixa" }, { k: "food", t: "Comida" }, { k: "water", t: "Água" }]
                AbstractButton {
                    id: chip
                    readonly property bool on: page.kindFilter === modelData.k
                    implicitHeight: 32; implicitWidth: chipRow.implicitWidth + T.s16 * 2
                    hoverEnabled: true
                    onClicked: page.kindFilter = modelData.k
                    background: Rectangle { radius: T.r4; color: chip.on ? T.haze : chip.hovered ? T.dusk : "transparent"
                        border.width: 1; border.color: chip.on ? T.fog : T.seam }
                    contentItem: Item { RowLayout { id: chipRow; anchors.centerIn: parent; spacing: T.s8
                        Rectangle { visible: modelData.k !== ""; width: T.s8; height: T.s8; radius: T.r2; color: T.kindColor(modelData.k) }
                        Label { text: modelData.t; color: chip.on ? T.moon : T.fog; font.pixelSize: T.body } } }
                }
            }
            Item { width: T.s16 }
            ComboBox {
                implicitHeight: 32 + T.s8
                model: ["Todos os gatos"].concat(backend.cats.map(c => c.name))
                onActivated: idx => page.catFilter = idx === 0 ? "" : currentText
                implicitWidth: 208
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: page.count === 0
        width: Math.min(page.width - T.s64, 480)
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
        text: backend.recent.length === 0 ? "Nenhuma visita registrada ainda. Elas aparecem aqui quando um gato passa por uma zona."
                                          : "Nenhuma visita com esse filtro."
        color: T.fog
    }

    // O ListView prende o delegate em x = 0: o item ocupa a largura toda e o cartão fica dentro.
    delegate: Item {
      width: page.width
      implicitHeight: row.implicitHeight
      required property var modelData
      Rectangle {
        id: row
        readonly property var v: parent.modelData
        readonly property bool hasDetails: (v.frames || 0) > 0
        x: T.s32
        width: page.width - T.s64
        implicitHeight: rowLayout.implicitHeight + T.s16
        radius: T.r8
        color: T.dusk
        border.width: 1; border.color: T.seam

        RowLayout {
            id: rowLayout
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: T.s8 }
            spacing: T.s16
            Rectangle {
                Layout.preferredWidth: 160; Layout.preferredHeight: 120
                radius: T.r4; color: T.night; clip: true
                Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                    source: row.v.photo === true && page.active ? backend.photoUrl(row.v.id) : "" }
                ColumnLayout { anchors.centerIn: parent; visible: row.v.photo !== true; spacing: T.s4
                    Icon { name: "camera"; color: T.fog; size: 20; Layout.alignment: Qt.AlignHCenter }
                    Label { text: "sem foto"; color: T.fog; font.pixelSize: T.caption } }
                MouseArea { anchors.fill: parent; enabled: row.v.photo === true; cursorShape: Qt.PointingHandCursor
                    onClicked: page.app.openPhoto(backend.photoUrl(row.v.id)) }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: T.s4
                RowLayout {
                    spacing: T.s8
                    Rectangle { width: T.s8; height: T.s8; radius: T.r2; color: T.kindColor(row.v.kind) }
                    Label { text: T.kindName[row.v.kind]; color: T.kindColor(row.v.kind); font.pixelSize: T.body; font.weight: Font.Medium }
                    Label { text: row.v.cat; color: T.moon; font.pixelSize: T.strong; font.weight: Font.DemiBold }
                }
                RowLayout {
                    spacing: T.s16
                    Label { text: new Date(row.v.start * 1000).toLocaleString(T.locale, "ddd d/M, HH:mm"); color: T.fog; font.features: { "tnum": 1 } }
                    // Presença: o tempo em que o gato foi visto de fato; visitas antigas só têm início e fim.
                    Label { text: "ficou " + Math.round(row.v.presence ?? (row.v.end - row.v.start)) + " s"; color: T.fog; font.features: { "tnum": 1 } }
                    Label { text: row.v.camera + ", " + row.v.zone; color: T.fog; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                // Certeza da identificação: barra e número.
                RowLayout {
                    visible: row.hasDetails
                    spacing: T.s8
                    Layout.topMargin: T.s4
                    Label { text: "Certeza"; color: T.fog; font.pixelSize: T.caption }
                    Rectangle {
                        width: T.s64; height: T.s4; radius: T.r2; color: T.haze
                        Rectangle { width: parent.width * Math.max(0, Math.min(1, row.v.score || 0)); height: parent.height; radius: T.r2
                            color: page.levelColor(row.v.score || 0) }
                    }
                    Label { text: row.v.score === null || row.v.score === undefined ? "sem dado"
                                  : Number(row.v.score).toLocaleString(T.locale, "f", 2) + " (" + page.level(row.v.score) + ")"
                        color: T.moon; font.pixelSize: T.caption; font.features: { "tnum": 1 } }
                }
                Label {
                    visible: row.hasDetails
                    text: {
                        const v = row.v.votes || {}
                        return row.v.frames + " quadros analisados. Votos: " + Object.keys(v).sort((a, b) => v[b] - v[a]).map(k => k + " " + v[k]).join(", ")
                    }
                    color: T.fog; font.pixelSize: T.caption; elide: Text.ElideRight; Layout.fillWidth: true
                }
                Label { visible: !row.hasDetails; text: "Visita registrada antes das fotos: sem certeza nem votos."; color: T.fog; font.pixelSize: T.caption }
            }
            ColumnLayout {
                spacing: T.s4
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                Layout.preferredWidth: 144
                ActionButton { Layout.fillWidth: true; text: "Trocar gato"; icon_: "swap-horizontal"; enabled: backend.cats.length > 0; onClicked: page.app.fixVisit(row.v.id) }
                ActionButton { Layout.fillWidth: true; text: "Apagar"; icon_: "delete-outline"; tint: T.alert
                    onClicked: { const id = row.v.id; page.app.ask("Apagar essa visita?", () => backend.deleteVisit(id)) } }
            }
        }
    }
      }
}
