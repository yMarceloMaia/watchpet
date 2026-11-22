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

    readonly property int online: backend.cameras.filter(c => c.online).length

    ColumnLayout {
        id: col
        x: T.s32; y: T.s32
        width: page.width - T.s64
        spacing: T.s16

        PageHeader {
            title: "Câmeras"
            subtitle: backend.cameras.length === 0 ? "Adicione uma câmera da rede, um celular ou a webcam deste PC."
                    : page.online + " de " + backend.cameras.length + (backend.cameras.length === 1 ? " câmera com imagem" : " câmeras com imagem")
        }

        GridLayout {
            id: grid
            Layout.fillWidth: true
            columns: Math.max(1, Math.floor((col.width + T.s16) / (416 + T.s16)))
            columnSpacing: T.s16; rowSpacing: T.s16
            Repeater {
                model: backend.cameras
                Panel {
                    id: card
                    readonly property var cam: modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    padding: T.s8
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: width * 9 / 16
                        radius: T.r4; color: T.night; clip: true
                        LiveImage {
                            anchors.fill: parent
                            camera: card.cam.name
                            // Só busca quadros com a página aberta, a janela à vista e a câmera no ar.
                            running: page.active && page.visible && Window.window !== null && Window.window.visible && card.cam.online
                        }
                        ColumnLayout {
                            visible: !card.cam.online
                            anchors.centerIn: parent
                            spacing: T.s8
                            Icon { name: "cctv"; size: 32; color: T.fog; Layout.alignment: Qt.AlignHCenter }
                            Label { text: card.cam.source === "push" ? "Sem imagem. Abra o app do celular na aba Câmera." : "Sem imagem. Confira se a câmera está ligada."
                                color: T.fog; font.pixelSize: T.caption; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                                Layout.maximumWidth: card.width - T.s64 }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: T.s8
                        spacing: T.s8
                        Rectangle { width: T.s8; height: T.s8; radius: T.r4; color: card.cam.online ? T.ok : T.alert }
                        Label { text: card.cam.name; font.pixelSize: T.strong; font.weight: Font.DemiBold; color: T.moon; elide: Text.ElideRight; Layout.fillWidth: true }
                        IconButton { icon_: "vector-polygon"; tip: "Desenhar zonas"; onClicked: page.app.editZones(card.cam) }
                        IconButton { icon_: "delete-outline"; tip: "Remover câmera"
                            onClicked: { const n = card.cam.name; page.app.ask("Remover a câmera “" + n + "” e as zonas dela?", () => backend.removeCamera(n)) } }
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.leftMargin: T.s8; Layout.bottomMargin: T.s4
                        spacing: T.s4
                        Repeater {
                            model: card.cam.zones
                            Rectangle {
                                width: zrow.implicitWidth + T.s16; height: 24
                                radius: T.r2; color: T.haze
                                RowLayout {
                                    id: zrow
                                    anchors.centerIn: parent
                                    spacing: T.s4
                                    Rectangle { width: T.s8; height: T.s8; radius: T.r2; color: T.kindColor(modelData.kind) }
                                    Label { text: modelData.name; font.pixelSize: T.caption; color: T.moon }
                                }
                            }
                        }
                        Label {
                            visible: card.cam.zones.length === 0
                            text: "Sem zonas: nada é contado nesta câmera ainda."
                            color: T.warn; font.pixelSize: T.caption
                        }
                    }
                }
            }
        }

        Panel {
            Layout.fillWidth: true
            title: "Adicionar câmera"
            subtitle: "Câmera IP: rtsp://usuário:senha@ip/stream. Celular com IP Webcam: http://ip:8080/video. Webcam deste PC: 0. App Catwatch no celular: push."
            RowLayout {
                Layout.fillWidth: true
                spacing: T.s8
                TextField { id: camName; placeholderText: "Nome (ex: cozinha)"; Layout.preferredWidth: 224 }
                TextField { id: camSource; placeholderText: "Endereço ou fonte"; Layout.fillWidth: true; onAccepted: addBtn.clicked() }
                ActionButton {
                    id: addBtn
                    text: "Adicionar"; icon_: "plus"; primary: true
                    enabled: camName.text.trim() !== "" && camSource.text.trim() !== ""
                    onClicked: { backend.addCamera(camName.text, camSource.text); camName.text = ""; camSource.text = "" }
                }
            }
        }
    }
}
