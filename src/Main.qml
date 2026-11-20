import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 980
    height: 700
    minimumWidth: 600
    minimumHeight: 440
    visible: true
    title: "Catwatch"
    color: "#0e0e10"

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    readonly property var kinds: ({ litter: "🚽 Caixa de areia", food: "🍽️ Comida", water: "💧 Água" })
    property bool helpVisible: false

    function typing() { return activeFocusItem instanceof TextInput }

    // Atalhos de letra só valem fora dos campos de texto, para não atrapalhar quem digita.
    Shortcut { sequence: "?"; enabled: !win.typing(); context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Q"; enabled: !win.typing(); context: Qt.ApplicationShortcut; onActivated: Qt.quit() }
    Shortcut { sequence: "R"; enabled: !win.typing(); context: Qt.ApplicationShortcut; onActivated: backend.refresh() }
    Shortcut { sequence: "1"; enabled: !win.typing(); context: Qt.ApplicationShortcut; onActivated: tabs.currentIndex = 0 }
    Shortcut { sequence: "2"; enabled: !win.typing(); context: Qt.ApplicationShortcut; onActivated: tabs.currentIndex = 1 }
    Shortcut { sequence: "3"; enabled: !win.typing(); context: Qt.ApplicationShortcut; onActivated: tabs.currentIndex = 2 }
    Shortcut { sequence: "4"; enabled: !win.typing(); context: Qt.ApplicationShortcut; onActivated: tabs.currentIndex = 3 }

    // Resultado das ações (salvar zonas, enviar fotos, erros do servidor...)
    Connections {
        target: backend
        function onMessage(text, isError) {
            toastLabel.text = text
            toast.isError = isError
            toast.opacity = 1
            toastTimer.restart()
        }
    }
    Rectangle {
        id: toast
        property bool isError: false
        z: 100
        opacity: 0
        visible: opacity > 0
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 20 }
        width: Math.min(parent.width - 40, toastLabel.implicitWidth + 32)
        height: toastLabel.implicitHeight + 20
        radius: theme.radius
        color: isError ? "#b3261e" : "#2b2b31"
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Label { id: toastLabel; anchors.centerIn: parent; width: parent.width - 32; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
        Timer { id: toastTimer; interval: 4000; onTriggered: toast.opacity = 0 }
    }

    FileDialog {
        id: photoDialog
        property string cat
        title: "Fotos de " + cat
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Imagens (*.jpg *.jpeg *.png *.webp)"]
        onAccepted: backend.addPhotos(cat, selectedFiles.map(u => u.toString()))
    }

    ZoneEditor { id: zoneEditor; objectName: "zoneEditor" }

    // Progresso do envio de fotos: bloqueia a janela até terminar, para ninguém clicar achando que travou.
    Popup {
        id: uploadPopup
        objectName: "uploadPopup"
        modal: true
        closePolicy: Popup.NoAutoClose
        anchors.centerIn: Overlay.overlay
        width: Math.min(win.width - 48, 400)
        padding: 20
        background: Rectangle { color: "#1b1b1f"; radius: theme.radius; border.color: "#ffffff1f" }
        Overlay.modal: Rectangle { color: "#000000aa" }
        contentItem: ColumnLayout {
            spacing: 12
            RowLayout {
                spacing: 12
                BusyIndicator { running: uploadPopup.visible; implicitWidth: 36; implicitHeight: 36 }
                Label { text: "Processando fotos de " + backend.uploadCat + "…"; font.bold: true; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
            ProgressBar {
                Layout.fillWidth: true
                from: 0; to: Math.max(1, backend.uploadTotal)
                value: backend.uploadDone
            }
            Label {
                text: backend.uploadDone + " de " + backend.uploadTotal + " — o servidor está analisando cada foto"
                opacity: .6
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }
    Connections {
        target: backend
        function onUploadChanged() {
            if (backend.uploading && !uploadPopup.visible) uploadPopup.open()
            else if (!backend.uploading && uploadPopup.visible) uploadPopup.close()
        }
    }

    Dialog {
        id: confirm
        property string text
        property var action
        anchors.centerIn: parent
        modal: true
        title: "Tem certeza?"
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label { text: confirm.text }
        onAccepted: if (action) action()
    }
    function ask(text, action) { confirm.text = text; confirm.action = action; confirm.open() }

    Menu {
        id: camMenu
        property string cat
        Repeater {
            model: backend.cameras
            MenuItem { text: modelData.name; onTriggered: backend.catFromCamera(camMenu.cat, modelData.name) }
        }
    }
    Menu {
        id: catMenu
        property int visitId
        Repeater {
            model: backend.cats
            MenuItem { text: modelData.name; onTriggered: backend.fixVisit(catMenu.visitId, modelData.name) }
        }
    }

    // ---------- Conexão ----------
    Item {
        anchors.fill: parent
        visible: !backend.connected
        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 380)
            spacing: 12
            Label { text: "🐱 Catwatch"; font.pixelSize: 28; Layout.alignment: Qt.AlignHCenter }
            TextField { id: urlField; Layout.fillWidth: true; placeholderText: "Servidor (192.168.0.10:8000)"; text: backend.savedUrl(); onAccepted: tokenField.forceActiveFocus() }
            TextField { id: tokenField; Layout.fillWidth: true; placeholderText: "Token (aparece no terminal do servidor)"; text: backend.savedToken(); echoMode: TextInput.Password
                onAccepted: backend.connectTo(urlField.text, text) }
            Label { text: backend.error; color: "#ff453a"; visible: text !== ""; wrapMode: Text.Wrap; Layout.fillWidth: true }
            Button { text: "Conectar"; highlighted: true; Layout.fillWidth: true; onClicked: backend.connectTo(urlField.text, tokenField.text) }
        }
    }

    // ---------- App ----------
    ColumnLayout {
        anchors.fill: parent
        visible: backend.connected
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            TabBar {
                id: tabs
                Layout.fillWidth: true
                TabButton { text: "Hoje (1)" }
                TabButton { text: "Câmeras (2)" }
                TabButton { text: "Gatos (3)" }
                TabButton { text: "Histórico (4)" }
            }
            ToolButton { text: "Sair"; onClicked: backend.disconnectServer() }
        }

        Label {
            visible: backend.error !== ""
            text: backend.error
            color: "#ff453a"
            Layout.margins: 8
        }

        StackLayout {
            currentIndex: tabs.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ===== Hoje =====
            Flickable {
                contentHeight: todayCol.height + 32
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: todayCol
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 12
                    Label { text: "Hoje"; font.pixelSize: 18; font.bold: true }
                    Label { visible: backend.today.length === 0; text: "Nenhuma visita registrada hoje."; opacity: .6 }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: backend.today
                            Rectangle {
                                id: todayCard
                                property var row: modelData
                                width: 260; height: 130
                                color: "#1b1b1f"; radius: theme.radius
                                border.color: "#ffffff1f"
                                Column {
                                    anchors.fill: parent; anchors.margins: 14; spacing: 10
                                    Label { text: "🐱 " + todayCard.row.cat; font.pixelSize: 18; font.bold: true }
                                    Row {
                                        spacing: 28
                                        Repeater {
                                            model: ["litter", "food", "water"]
                                            Column {
                                                Label { text: ({ litter: "🚽", food: "🍽️", water: "💧" })[modelData]; font.pixelSize: 22; anchors.horizontalCenter: parent.horizontalCenter }
                                                Label { text: Number(todayCard.row[modelData]); font.pixelSize: 32; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Label { text: "Últimos 7 dias"; font.pixelSize: 18; font.bold: true; Layout.topMargin: 12 }
                    Label { visible: backend.week.length === 0; text: "Sem dados ainda."; opacity: .6 }
                    Repeater {
                        model: backend.week
                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            color: "#1b1b1f"; radius: theme.radius
                            RowLayout {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                Label { text: new Date(modelData.day + "T12:00:00").toLocaleDateString(Qt.locale(), Locale.ShortFormat); opacity: .6; Layout.preferredWidth: 110 }
                                Label { text: "🐱 " + modelData.cat; Layout.fillWidth: true }
                                Label { text: "🚽 " + modelData.litter + "    🍽️ " + modelData.food + "    💧 " + modelData.water }
                            }
                        }
                    }
                }
            }

            // ===== Câmeras =====
            Flickable {
                contentHeight: camCol.height + 32
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: camCol
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 12

                    Flow {
                        id: camFlow
                        Layout.fillWidth: true
                        spacing: 12
                        // Quantas câmeras cabem por linha com pelo menos 320px cada.
                        readonly property int columns: Math.max(1, Math.floor((width + spacing) / (320 + spacing)))
                        readonly property real cardWidth: Math.floor((width - spacing * (columns - 1)) / columns)
                        Repeater {
                            model: backend.cameras
                            Rectangle {
                                width: camFlow.cardWidth
                                height: width * 9 / 16 + 40
                                color: "#1b1b1f"; radius: theme.radius
                                Image {
                                    // Só busca imagem com esta aba aberta e a câmera online, para não gastar rede e CPU à toa.
                                    source: tabs.currentIndex === 1 && modelData.online ? backend.snapshotUrl(modelData.name, backend.frame) : ""
                                    cache: false
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    anchors { left: parent.left; right: parent.right; top: parent.top }
                                    height: parent.height - 40
                                }
                                Label {
                                    visible: !modelData.online
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: -20
                                    text: "Sem sinal"
                                    opacity: .5
                                }
                                RowLayout {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8 }
                                    height: 40
                                    Label {
                                        text: (modelData.online ? "● " : "○ ") + modelData.name + "  ·  " + modelData.zones.length + " zonas"
                                        color: modelData.online ? "#30d158" : "#ff453a"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    ToolButton { text: "Zonas"; onClicked: zoneEditor.openFor(modelData) }
                                    ToolButton { text: "Remover"
                                        onClicked: { const n = modelData.name; win.ask("Remover a câmera “" + n + "” e suas zonas?", () => backend.removeCamera(n)) } }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: addCol.implicitHeight + 28
                        color: "#1b1b1f"; radius: theme.radius
                        ColumnLayout {
                            id: addCol
                            anchors { fill: parent; margins: 14 }
                            spacing: 8
                            Label { text: "Adicionar câmera"; font.bold: true }
                            RowLayout {
                                spacing: 8
                                TextField { id: camName; placeholderText: "Nome (ex: cozinha)"; Layout.preferredWidth: 200 }
                                TextField { id: camSource; Layout.fillWidth: true; placeholderText: "rtsp://…  |  http://ip:8080/video  |  0 (webcam deste PC)  |  push" }
                                Button {
                                    text: "Adicionar"; highlighted: true
                                    enabled: camName.text.trim() !== "" && camSource.text.trim() !== ""
                                    onClicked: { backend.addCamera(camName.text, camSource.text); camName.text = ""; camSource.text = "" }
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                opacity: .6
                                text: "Celular: use o app Catwatch (aba Câmera) com a fonte “push”, ou o app IP Webcam com http://IP:8080/video."
                            }
                        }
                    }
                }
            }

            // ===== Gatos =====
            Flickable {
                contentHeight: catsCol.height + 32
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: catsCol
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 12
                    Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: backend.cats
                            Rectangle {
                                width: 390; height: 120
                                color: "#1b1b1f"; radius: theme.radius
                                RowLayout {
                                    anchors { fill: parent; margins: 12 }
                                    spacing: 12
                                    Rectangle {
                                        Layout.preferredWidth: 72; Layout.preferredHeight: 72
                                        Layout.alignment: Qt.AlignTop
                                        color: "#333"; radius: theme.radius
                                        clip: true
                                        Image {
                                            anchors.fill: parent
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: false
                                            source: tabs.currentIndex === 2 ? backend.thumbUrl(modelData.name, backend.catsRevision) : ""
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        Label { text: modelData.name; font.pixelSize: 17; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                        Label { text: modelData.photos + (modelData.photos === 1 ? " foto" : " fotos") + (modelData.photos < 15 ? " · ideal 15+" : ""); opacity: .6 }
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Button { text: "Fotos…"; flat: true; onClicked: { photoDialog.cat = modelData.name; photoDialog.open() } }
                                            Button { text: "Da câmera"; flat: true; enabled: backend.cameras.length > 0
                                                onClicked: { camMenu.cat = modelData.name; camMenu.popup() } }
                                            Button { text: "Apagar"; flat: true; Material.foreground: "#ff453a"
                                                onClicked: { const n = modelData.name; win.ask("Apagar " + n + " e todas as fotos?", () => backend.deleteCat(n)) } }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: newCatCol.implicitHeight + 28
                        color: "#1b1b1f"; radius: theme.radius
                        ColumnLayout {
                            id: newCatCol
                            anchors { fill: parent; margins: 14 }
                            spacing: 8
                            Label { text: "Novo gato"; font.bold: true }
                            Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .6
                                text: "Cadastre cada gato com 15–30 fotos de ângulos e luz diferentes, incluindo perto da caixa e do comedouro." }
                            RowLayout {
                                spacing: 8
                                TextField { id: newCat; placeholderText: "Nome do gato"; Layout.preferredWidth: 220 }
                                Button {
                                    text: "Escolher fotos…"; highlighted: true
                                    enabled: newCat.text.trim() !== ""
                                    onClicked: { photoDialog.cat = newCat.text.trim(); photoDialog.open() }
                                }
                                Button {
                                    text: "Foto da câmera"; flat: true
                                    enabled: newCat.text.trim() !== "" && backend.cameras.length > 0
                                    onClicked: { camMenu.cat = newCat.text.trim(); camMenu.popup() }
                                }
                            }
                        }
                    }
                }
            }

            // ===== Histórico =====
            ListView {
                clip: true
                model: backend.recent
                spacing: 8
                topMargin: 12; bottomMargin: 12
                ScrollBar.vertical: ScrollBar {}
                Label { anchors.centerIn: parent; visible: backend.recent.length === 0; text: "Sem visitas ainda."; opacity: .6 }
                delegate: Item {
                    id: visit
                    // Quão confiável é o nome: similaridade média dos quadros em que o gato foi reconhecido.
                    readonly property string level: modelData.score === null || modelData.score === undefined ? "—"
                        : modelData.score >= 0.85 ? "alta" : modelData.score >= 0.75 ? "média" : "baixa"
                    readonly property string votes: {
                        const v = modelData.votes || {}
                        return Object.keys(v).sort((a, b) => v[b] - v[a]).map(k => k + " " + v[k]).join(" · ")
                    }
                    width: ListView.view.width - 32
                    x: 16
                    height: 116
                    Rectangle {
                        anchors.fill: parent
                        color: "#1b1b1f"; radius: theme.radius
                        RowLayout {
                            anchors { fill: parent; margins: 8 }
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 134; Layout.preferredHeight: 100
                                color: "#2a2a30"; radius: theme.radius; clip: true
                                Image {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    // Só busca a foto com a aba aberta; o cache do Qt evita rebaixar a cada atualização.
                                    source: modelData.photo && tabs.currentIndex === 3 ? backend.photoUrl(modelData.id) : ""
                                }
                                Label { anchors.centerIn: parent; text: "sem foto"; opacity: .5; visible: !modelData.photo }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: modelData.photo
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { preview.source = backend.photoUrl(modelData.id); preview.open() }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label { text: win.kinds[modelData.kind] + "  —  " + modelData.cat; font.bold: true; font.pixelSize: 16; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { opacity: .6; elide: Text.ElideRight; Layout.fillWidth: true
                                    text: new Date(modelData.start * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat) + "  ·  " + Math.round(modelData.end - modelData.start) + "s  ·  câmera " + modelData.camera + "  ·  zona " + modelData.zone }
                                // Visitas gravadas antes do recurso de fotos não têm detalhes.
                                Label { Layout.fillWidth: true; elide: Text.ElideRight
                                    visible: modelData.frames > 0
                                    text: "Certeza: " + (modelData.score === null || modelData.score === undefined ? "—" : Number(modelData.score).toFixed(2)) + " (" + visit.level + ")"
                                        + (modelData.conf ? "  ·  detecção " + Number(modelData.conf).toFixed(2) : "") }
                                Label { opacity: .6; elide: Text.ElideRight; Layout.fillWidth: true
                                    text: modelData.frames > 0 ? modelData.frames + " quadros  ·  votos: " + (visit.votes || "—")
                                                               : "Visita antiga: sem foto nem certeza registradas" }
                            }
                            ColumnLayout {
                                spacing: 0
                                Button { text: "Trocar gato"; flat: true; enabled: backend.cats.length > 0
                                    onClicked: { catMenu.visitId = modelData.id; catMenu.popup() } }
                                Button { text: "Apagar"; flat: true; Material.foreground: "#ff453a"
                                    onClicked: { const id = modelData.id; win.ask("Apagar essa visita?", () => backend.deleteVisit(id)) } }
                            }
                        }
                    }
                }
            }
        }
    }

    // Foto da visita em tamanho grande
    Popup {
        id: preview
        property alias source: bigPhoto.source
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(parent.width - 40, 960)
        height: Math.min(parent.height - 40, 720)
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "#000"; radius: theme.radius }
        Image { id: bigPhoto; anchors.fill: parent; fillMode: Image.PreserveAspectFit; asynchronous: true }
        MouseArea { anchors.fill: parent; onClicked: preview.close() }
    }

    // ---------- Ajuda ----------
    Rectangle {
        anchors.fill: parent
        z: 200
        visible: win.helpVisible
        color: "#000000cc"
        MouseArea { anchors.fill: parent; onClicked: win.helpVisible = false }
        Column {
            anchors.centerIn: parent
            spacing: 6
            Label { text: "Atalhos"; font.bold: true; font.pixelSize: 20 }
            Label { text: "1 / 2 / 3 / 4   Hoje · Câmeras · Gatos · Histórico" }
            Label { text: "R   Atualizar" }
            Label { text: "?   Esta ajuda" }
            Label { text: "Q   Sair" }
        }
    }
}
