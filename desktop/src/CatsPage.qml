import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

Flickable {
    id: page
    property var app
    property bool active: false
    contentHeight: col.implicitHeight + T.s64
    clip: true
    ScrollBar.vertical: ScrollBar {}
    readonly property int ideal: 15

    ColumnLayout {
        id: col
        x: T.s32; y: T.s32
        width: page.width - T.s64
        spacing: T.s16

        PageHeader {
            title: "Gatos"
            subtitle: "O Catwatch reconhece cada gato comparando com estas fotos. Quanto mais variadas (ângulos, luz, perto da caixa e do pote), melhor."
        }

        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(1, Math.floor((col.width + T.s16) / (400 + T.s16)))
            columnSpacing: T.s16; rowSpacing: T.s16
            Repeater {
                model: backend.cats
                Panel {
                    id: card
                    readonly property var cat: modelData
                    readonly property real quality: Math.min(1, cat.photos / page.ideal)
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: T.s16
                        Rectangle {
                            Layout.preferredWidth: T.s64 + T.s16; Layout.preferredHeight: T.s64 + T.s16
                            Layout.alignment: Qt.AlignTop
                            radius: T.r4; color: T.haze; clip: true
                            Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
                                source: page.active ? backend.thumbUrl(card.cat.name, backend.catsRevision) : "" }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: T.s8
                            Label { text: card.cat.name; font.pixelSize: T.title; font.weight: Font.DemiBold; color: T.moon; elide: Text.ElideRight; Layout.fillWidth: true }
                            // Medidor de fotos: cheio a partir do ideal.
                            Rectangle {
                                Layout.fillWidth: true; height: T.s4; radius: T.r2; color: T.haze
                                Rectangle { width: parent.width * card.quality; height: parent.height; radius: T.r2
                                    color: card.quality >= 1 ? T.ok : T.warn }
                            }
                            Label {
                                text: card.cat.photos + (card.cat.photos === 1 ? " foto" : " fotos")
                                      + (card.cat.photos < page.ideal ? ", faltam " + (page.ideal - card.cat.photos) + " para o ideal" : "")
                                color: T.fog; font.pixelSize: T.caption
                            }
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: T.s8
                        ActionButton { text: "Adicionar fotos"; icon_: "image-multiple"; onClicked: page.app.pickPhotos(card.cat.name) }
                        ActionButton { text: "Foto da câmera"; icon_: "camera"; enabled: backend.cameras.length > 0
                            onClicked: page.app.photoFromCamera(card.cat.name) }
                        ActionButton { text: "Apagar"; icon_: "delete-outline"; tint: T.alert
                            onClicked: { const n = card.cat.name; page.app.ask("Apagar " + n + " e todas as fotos dele?", () => backend.deleteCat(n)) } }
                    }
                }
            }
        }

        Panel {
            Layout.fillWidth: true
            title: backend.cats.length ? "Cadastrar outro gato" : "Cadastrar o primeiro gato"
            subtitle: "Dê um nome e escolha fotos do computador, ou tire uma foto pela câmera com o gato à vista."
            RowLayout {
                Layout.fillWidth: true
                spacing: T.s8
                TextField { id: newCat; placeholderText: "Nome do gato"; Layout.preferredWidth: 256 }
                ActionButton { text: "Escolher fotos"; icon_: "image-multiple"; primary: true; enabled: newCat.text.trim() !== ""
                    onClicked: page.app.pickPhotos(newCat.text.trim()) }
                ActionButton { text: "Foto da câmera"; icon_: "camera"; enabled: newCat.text.trim() !== "" && backend.cameras.length > 0
                    onClicked: page.app.photoFromCamera(newCat.text.trim()) }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
