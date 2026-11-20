import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

// Hoje: alertas, a faixa do dia de cada gato e a semana.
Flickable {
    id: page
    property var app
    contentHeight: col.implicitHeight + T.s64
    clip: true
    ScrollBar.vertical: ScrollBar {}

    property real midnight: { const d = new Date(); d.setHours(0, 0, 0, 0); return d.getTime() / 1000 }
    property real now: Date.now() / 1000
    Timer { interval: 30000; running: true; repeat: true; onTriggered: { page.now = Date.now() / 1000
            const d = new Date(); d.setHours(0, 0, 0, 0); page.midnight = d.getTime() / 1000 } }

    // Visitas de hoje agrupadas por gato, vindas do histórico recente.
    readonly property var byCat: {
        const out = {}
        for (const v of backend.recent)
            if (v.start >= midnight) (out[v.cat] = out[v.cat] || []).push(v)
        return out
    }
    readonly property var cats: {
        const names = backend.today.map(r => r.cat)
        for (const c of backend.cats) if (names.indexOf(c.name) < 0) names.push(c.name)
        return names
    }
    function countOf(cat, kind) {
        const row = backend.today.find(r => r.cat === cat)
        return row ? Number(row[kind]) : 0
    }
    function lastVisit(cat) {
        const list = byCat[cat] || []
        return list.length ? list.reduce((a, b) => a.start > b.start ? a : b) : null
    }

    ColumnLayout {
        id: col
        x: T.s32; y: T.s32
        width: page.width - T.s64
        spacing: T.s16

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Hoje"; font.pixelSize: T.display; font.weight: Font.Bold; color: T.moon }
            Item { Layout.fillWidth: true }
            Label { text: new Date().toLocaleDateString(T.locale, "dddd, d 'de' MMMM"); color: T.fog; font.pixelSize: T.body }
        }

        // Alertas do dia: a faixa à esquerda tem a cor da gravidade.
        Repeater {
            model: backend.alertsToday
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: alertRow.implicitHeight + T.s16 * 2
                radius: T.r8
                color: T.dusk
                border.width: 1; border.color: T.seam
                Rectangle { width: T.s4; height: parent.height - T.s16; y: T.s8; x: T.s8; radius: T.r2; color: T.levelColor(modelData.level) }
                RowLayout {
                    id: alertRow
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: T.s32; rightMargin: T.s16 }
                    spacing: T.s8
                    Icon { name: modelData.level === "error" ? "alert" : "alert-circle"; color: T.levelColor(modelData.level); size: 20 }
                    Label { text: modelData.message; color: T.moon; font.pixelSize: T.strong; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label { text: new Date(modelData.ts * 1000).toLocaleTimeString(T.locale, "HH:mm"); color: T.fog; font.features: { "tnum": 1 } }
                }
            }
        }

        // Sem gatos e sem visitas: o próximo passo.
        Panel {
            visible: page.cats.length === 0
            Layout.fillWidth: true
            title: "Nenhum gato cadastrado ainda"
            subtitle: "Cadastre cada gato com fotos para o Catwatch saber quem é quem. Depois, desenhe as zonas da caixa, da comida e da água nas câmeras."
            RowLayout {
                spacing: T.s8
                Button { text: "Cadastrar um gato"; highlighted: true; onClicked: page.app.goTo(2) }
                Button { text: "Desenhar zonas"; flat: true; onClicked: page.app.goTo(1) }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: col.width >= 1280 ? 2 : 1
            columnSpacing: T.s16; rowSpacing: T.s16
            Repeater {
                model: page.cats
                Panel {
                    id: catPanel
                    readonly property string cat: modelData
                    readonly property var last: page.lastVisit(cat)
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: T.s16
                        Rectangle {
                            Layout.preferredWidth: T.s32 + T.s8; Layout.preferredHeight: T.s32 + T.s8
                            radius: T.r4; color: T.haze; clip: true
                            Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true
                                source: page.visible ? backend.thumbUrl(catPanel.cat, backend.catsRevision) : "" }
                        }
                        ColumnLayout {
                            spacing: T.s2
                            Layout.fillWidth: true
                            Label { text: catPanel.cat; font.pixelSize: T.title; font.weight: Font.DemiBold; color: T.moon; elide: Text.ElideRight; Layout.fillWidth: true }
                            Label {
                                text: catPanel.last ? "Última visita: " + T.kindName[catPanel.last.kind].toLowerCase() + " às "
                                                      + new Date(catPanel.last.start * 1000).toLocaleTimeString(T.locale, "HH:mm")
                                                    : "Nenhuma visita hoje"
                                color: T.fog; font.pixelSize: T.caption
                            }
                        }
                        Repeater {
                            model: ["litter", "food", "water"]
                            KindTag { kind: modelData; count: page.countOf(catPanel.cat, modelData); Layout.leftMargin: T.s8 }
                        }
                    }
                    DayStrip {
                        Layout.fillWidth: true
                        Layout.topMargin: T.s8
                        visits: page.byCat[catPanel.cat] || []
                        dayStart: page.midnight
                        now: page.now
                    }
                }
            }
        }

        // A semana: um dia por linha, as três contagens na cor de cada tipo.
        Panel {
            visible: backend.week.length > 0
            Layout.fillWidth: true
            title: "Últimos 7 dias"
            RowLayout {
                Layout.fillWidth: true
                spacing: T.s16
                Label { text: "Dia"; color: T.fog; font.pixelSize: T.caption; Layout.preferredWidth: 128 }
                Label { text: "Gato"; color: T.fog; font.pixelSize: T.caption; Layout.fillWidth: true }
                Repeater { model: ["litter", "food", "water"]; KindTag { kind: modelData; Layout.preferredWidth: 96 } }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: T.seam }
            Repeater {
                model: backend.week
                RowLayout {
                    id: weekRow
                    readonly property var row: modelData
                    Layout.fillWidth: true
                    spacing: T.s16
                    Label { text: new Date(weekRow.row.day + "T12:00:00").toLocaleDateString(T.locale, "ddd, d/M")
                        color: T.fog; font.features: { "tnum": 1 }; Layout.preferredWidth: 128 }
                    Label { text: weekRow.row.cat; color: T.moon; Layout.fillWidth: true; elide: Text.ElideRight }
                    Repeater {
                        model: ["litter", "food", "water"]
                        Label {
                            text: String(weekRow.row[modelData])
                            color: Number(weekRow.row[modelData]) ? T.kindColor(modelData) : T.fog
                            font.pixelSize: T.strong; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                            Layout.preferredWidth: 96
                        }
                    }
                }
            }
        }
    }
}
