import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Desenha as zonas (caixa de areia, comida, água) por cima de uma imagem da câmera.
Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: Overlay.overlay
    width: Overlay.overlay ? Overlay.overlay.width - 40 : 800
    height: Overlay.overlay ? Overlay.overlay.height - 40 : 600
    padding: 14
    background: Rectangle { color: "#16161a"; radius: theme.radius; border.color: "#ffffff1f" }

    property string camera: ""
    property var zones: []
    property var cur: []
    readonly property var kindNames: ({ litter: "Caixa de areia", food: "Comida", water: "Água" })
    readonly property var kindColors: ({ litter: "#ff9f0a", food: "#30d158", water: "#0a84ff" })

    function openFor(cam) {
        camera = cam.name
        zones = JSON.parse(JSON.stringify(cam.zones))
        cur = []
        zoneName.text = ""
        photo.source = backend.snapshotUrl(cam.name, Date.now(), true)
        open()
    }

    function closeZone() {
        if (cur.length < 3 || zoneName.text.trim() === "") {
            hint.text = "Marque 3 ou mais pontos e dê um nome à zona."
            return
        }
        hint.text = ""
        zones = zones.concat([{ name: zoneName.text.trim(), kind: kindBox.currentValue, polygon: cur }])
        cur = []
        zoneName.text = ""
        canvas.requestPaint()
    }

    contentItem: ColumnLayout {
        spacing: 8
        Label { text: "Zonas — " + root.camera; font.pixelSize: 18; font.bold: true }
        Label { text: "Clique na imagem para marcar os cantos da área e depois em “Fechar zona”."; opacity: .6 }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Image {
                id: photo
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                cache: false
                onStatusChanged: canvas.requestPaint()
            }
            Label {
                anchors.centerIn: parent
                visible: photo.status === Image.Error || photo.status === Image.Null
                text: "Sem imagem da câmera (ela precisa estar online)"
                opacity: .6
            }
            Canvas {
                id: canvas
                anchors.fill: parent
                // Área realmente ocupada pela imagem dentro do item (PreserveAspectFit deixa faixas).
                readonly property real ox: (width - photo.paintedWidth) / 2
                readonly property real oy: (height - photo.paintedHeight) / 2
                onPaint: {
                    const c = getContext("2d")
                    c.clearRect(0, 0, width, height)
                    const px = p => [ox + p[0] * photo.paintedWidth, oy + p[1] * photo.paintedHeight]
                    function path(poly, close) {
                        c.beginPath()
                        poly.forEach((p, i) => { const q = px(p); i ? c.lineTo(q[0], q[1]) : c.moveTo(q[0], q[1]) })
                        if (close) c.closePath()
                    }
                    root.zones.forEach(z => {
                        const col = root.kindColors[z.kind]
                        path(z.polygon, true)
                        c.fillStyle = col + "55"; c.fill()
                        c.strokeStyle = col; c.lineWidth = 2; c.stroke()
                    })
                    if (root.cur.length) {
                        path(root.cur, false)
                        c.strokeStyle = "#00e5ff"; c.lineWidth = 2; c.stroke()
                        root.cur.forEach(p => {
                            const q = px(p)
                            c.beginPath(); c.arc(q[0], q[1], 5, 0, 7); c.fillStyle = "#00e5ff"; c.fill()
                        })
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => {
                        const w = photo.paintedWidth, h = photo.paintedHeight
                        if (w <= 0 || h <= 0) return
                        const x = (mouse.x - canvas.ox) / w, y = (mouse.y - canvas.oy) / h
                        if (x < 0 || x > 1 || y < 0 || y > 1) return
                        root.cur = root.cur.concat([[x, y]])
                        canvas.requestPaint()
                    }
                }
            }
        }

        RowLayout {
            spacing: 8
            TextField { id: zoneName; placeholderText: "Nome da zona (ex: bebedouro)"; Layout.fillWidth: true }
            ComboBox {
                id: kindBox
                Layout.preferredWidth: 190
                textRole: "text"; valueRole: "value"
                model: [{ text: "Caixa de areia", value: "litter" }, { text: "Comida", value: "food" }, { text: "Água", value: "water" }]
            }
            Button { text: "Fechar zona"; onClicked: root.closeZone() }
            Button { text: "Desfazer ponto"; flat: true; onClicked: { root.cur = root.cur.slice(0, -1); canvas.requestPaint() } }
        }
        Label { id: hint; color: "#ff453a"; visible: text !== "" }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: root.zones
                Button {
                    flat: true
                    text: modelData.name + " (" + root.kindNames[modelData.kind] + ")  ✕"
                    Material.foreground: root.kindColors[modelData.kind]
                    onClicked: { root.zones = root.zones.filter((_, i) => i !== index); canvas.requestPaint() }
                }
            }
        }

        RowLayout {
            Button { text: "Salvar zonas"; highlighted: true; onClicked: { backend.setZones(root.camera, root.zones); root.close() } }
            Button { text: "Cancelar"; flat: true; onClicked: root.close() }
        }
    }
}
