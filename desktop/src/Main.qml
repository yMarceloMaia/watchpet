import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts
import "."

ApplicationWindow {
    id: win
    width: 1280
    height: 800
    minimumWidth: 720
    minimumHeight: 480
    visible: !startHidden
    title: "Catwatch"
    color: T.night
    font.family: T.family
    font.pixelSize: T.body

    // Automático segue o tema do Omarchy (claro quando o colors.toml diz mode = "light").
    Binding { target: T; property: "dark"; value: shell.themeMode === "dark" || (shell.themeMode === "auto" && !theme.light) }
    Material.theme: T.dark ? Material.Dark : Material.Light
    Material.accent: theme.accent
    Material.background: T.dusk
    Material.foreground: T.moon
    Material.roundedScale: Material.ExtraSmallScale   // cantos de 4 nos controles
    Material.containerStyle: Material.Outlined

    readonly property var pages: [
        { title: "Hoje", icon: "paw" }, { title: "Câmeras", icon: "cctv" }, { title: "Gatos", icon: "cat" },
        { title: "Histórico", icon: "history" }, { title: "Servidor", icon: "server" }
    ]
    property int current: 0
    property bool helpVisible: false

    // ---------- API para as páginas ----------
    function goTo(i) { current = i }
    function ask(text, action) { confirm.text = text; confirm.action = action; confirm.open() }
    function pickPhotos(cat) { photoDialog.cat = cat; photoDialog.open() }
    function photoFromCamera(cat) { camMenu.cat = cat; camMenu.popup() }
    function fixVisit(id) { catMenu.visitId = id; catMenu.popup() }
    function openPhoto(url) { preview.source = url; preview.open() }
    function editZones(cam) { zoneEditor.openFor(cam) }
    function typing() { return activeFocusItem instanceof TextInput }

    // Fechar a janela: fica na bandeja (o servidor segue monitorando) ou sai de vez.
    onClosing: close => {
        if (shell.runInBackground && shell.trayAvailable) {
            close.accepted = false
            win.hide()
        } else {
            shell.quit()
        }
    }
    function quitApp() {
        if (server.owned)
            ask("Sair do Catwatch? O servidor deste PC será parado e as câmeras deixam de ser monitoradas.", () => shell.quit())
        else
            shell.quit()
    }
    Connections {
        target: shell
        function onShowWindowRequested() { win.show(); win.raise(); win.requestActivate() }
    }

    // Atalhos de letra só valem fora dos campos de texto.
    Shortcut { sequence: "?"; enabled: !win.typing(); context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Q"; enabled: !win.typing(); context: Qt.ApplicationShortcut; onActivated: win.quitApp() }
    Shortcut { sequence: "R"; enabled: !win.typing(); context: Qt.ApplicationShortcut; onActivated: backend.refresh() }
    Shortcut { sequence: "1"; enabled: !win.typing() && backend.connected; context: Qt.ApplicationShortcut; onActivated: win.current = 0 }
    Shortcut { sequence: "2"; enabled: !win.typing() && backend.connected; context: Qt.ApplicationShortcut; onActivated: win.current = 1 }
    Shortcut { sequence: "3"; enabled: !win.typing() && backend.connected; context: Qt.ApplicationShortcut; onActivated: win.current = 2 }
    Shortcut { sequence: "4"; enabled: !win.typing() && backend.connected; context: Qt.ApplicationShortcut; onActivated: win.current = 3 }
    Shortcut { sequence: "5"; enabled: !win.typing() && backend.connected; context: Qt.ApplicationShortcut; onActivated: win.current = 4 }

    // ---------- Avisos curtos ----------
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
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: T.s32 }
        width: Math.min(parent.width - T.s64, toastRow.implicitWidth + T.s32)
        height: toastRow.implicitHeight + T.s16
        radius: T.r4
        color: T.haze
        border.width: 1; border.color: isError ? T.alert : T.seam
        Behavior on opacity { NumberAnimation { duration: 160 } }
        RowLayout {
            id: toastRow
            anchors.centerIn: parent
            spacing: T.s8
            Icon { name: toast.isError ? "alert-circle" : "check-circle"; color: toast.isError ? T.alert : T.ok }
            Label { id: toastLabel; color: T.moon; wrapMode: Text.Wrap; Layout.maximumWidth: win.width - T.s64 * 2 }
        }
        Timer { id: toastTimer; interval: 4000; onTriggered: toast.opacity = 0 }
    }

    // ---------- Diálogos compartilhados ----------
    FileDialog {
        id: photoDialog
        property string cat
        title: "Fotos de " + cat
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Imagens (*.jpg *.jpeg *.png *.webp)"]
        onAccepted: backend.addPhotos(cat, selectedFiles.map(u => u.toString()))
    }

    ZoneEditor { id: zoneEditor; objectName: "zoneEditor" }

    Dialog {
        id: confirm
        property string text
        property var action
        anchors.centerIn: parent
        width: Math.min(win.width - T.s64, 448)
        modal: true
        title: "Tem certeza?"
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label { text: confirm.text; wrapMode: Text.Wrap; width: parent.width; color: T.moon }
        onAccepted: if (action) action()
    }

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

    // Foto da visita em tamanho grande.
    Popup {
        id: preview
        property alias source: bigPhoto.source
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(parent.width - T.s64, 1024)
        height: Math.min(parent.height - T.s64, 768)
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "black"; radius: T.r8 }
        Overlay.modal: Rectangle { color: T.scrim }
        Image { id: bigPhoto; anchors.fill: parent; fillMode: Image.PreserveAspectFit; asynchronous: true }
        MouseArea { anchors.fill: parent; onClicked: preview.close() }
    }

    // Progresso do envio de fotos: bloqueia a janela até terminar.
    Popup {
        id: uploadPopup
        objectName: "uploadPopup"
        modal: true
        closePolicy: Popup.NoAutoClose
        anchors.centerIn: Overlay.overlay
        width: Math.min(win.width - T.s64, 416)
        padding: T.s16
        background: Rectangle { color: T.dusk; radius: T.r8; border.width: 1; border.color: T.seam }
        Overlay.modal: Rectangle { color: T.scrim }
        contentItem: ColumnLayout {
            spacing: T.s16
            RowLayout {
                spacing: T.s16
                BusyIndicator { running: uploadPopup.visible; implicitWidth: 32; implicitHeight: 32 }
                ColumnLayout {
                    spacing: T.s2
                    Label { text: "Processando fotos de " + backend.uploadCat; color: T.moon; font.pixelSize: T.strong; font.weight: Font.DemiBold }
                    Label { text: "O servidor procura o gato em cada foto."; color: T.fog; font.pixelSize: T.caption }
                }
            }
            ProgressBar { Layout.fillWidth: true; from: 0; to: Math.max(1, backend.uploadTotal); value: backend.uploadDone }
            Label { text: backend.uploadDone + " de " + backend.uploadTotal; color: T.fog; font.features: { "tnum": 1 } }
        }
    }
    Connections {
        target: backend
        function onUploadChanged() {
            if (backend.uploading && !uploadPopup.visible) uploadPopup.open()
            else if (!backend.uploading && uploadPopup.visible) uploadPopup.close()
        }
    }

    // ---------- Conexão ----------
    Item {
        anchors.fill: parent
        visible: !backend.connected
        Panel {
            anchors.centerIn: parent
            width: Math.min(parent.width - T.s64, 416)
            padding: T.s32
            ColumnLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: T.s16
                spacing: T.s4
                Icon { name: "cat"; size: T.s32; color: theme.accent }
                Label { text: "Catwatch"; font.pixelSize: T.display; font.weight: Font.Bold; color: T.moon }
                Label { text: "Caixa, comida e água de cada gato, ao longo do dia."; color: T.fog; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
            TextField { id: urlField; Layout.fillWidth: true; placeholderText: "Servidor, ex: 192.168.0.10:8000"; text: backend.savedUrl(); onAccepted: tokenField.forceActiveFocus() }
            TextField { id: tokenField; Layout.fillWidth: true; placeholderText: "Token"; text: backend.savedToken(); echoMode: TextInput.Password
                onAccepted: backend.connectTo(urlField.text, text) }
            Label { text: backend.error; color: T.alert; visible: text !== ""; wrapMode: Text.Wrap; Layout.fillWidth: true }
            ActionButton { text: "Conectar"; primary: true; Layout.fillWidth: true; onClicked: backend.connectTo(urlField.text, tokenField.text) }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: T.s16
                spacing: T.s8
                Rectangle { height: 1; color: T.seam; Layout.fillWidth: true }
                Label { text: "ou use o servidor deste PC"; color: T.fog; font.pixelSize: T.caption }
                Rectangle { height: 1; color: T.seam; Layout.fillWidth: true }
            }
            ActionButton {
                Layout.fillWidth: true
                icon_: server.state === "running" || server.state === "external" ? "server" : "play"
                enabled: server.serverDirValid && server.state !== "starting" && server.state !== "stopping"
                text: server.state === "running" || server.state === "external" ? "Conectar ao servidor deste PC" : "Iniciar o servidor deste PC"
                onClicked: server.state === "running" || server.state === "external"
                           ? backend.connectTo(server.localUrl(), server.localToken()) : server.start()
            }
            RowLayout {
                Layout.fillWidth: true
                visible: server.state === "starting" || server.message !== ""
                spacing: T.s8
                BusyIndicator { running: server.state === "starting"; visible: running; implicitWidth: 24; implicitHeight: 24 }
                Label { text: server.message; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: T.caption
                    color: server.state === "error" ? T.alert : T.fog }
            }
            Label {
                visible: !server.serverDirValid
                text: "Servidor deste PC não encontrado. Rode o install.sh ou defina CATWATCH_SERVER_DIR."
                color: T.fog; font.pixelSize: T.caption; wrapMode: Text.Wrap; Layout.fillWidth: true
            }
        }
    }

    // ---------- App ----------
    RowLayout {
        anchors.fill: parent
        visible: backend.connected
        spacing: 0

        // Trilho de navegação, com o estado do servidor no pé.
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 224
            color: T.dusk
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: T.seam }

            ColumnLayout {
                anchors { fill: parent; margins: T.s16 }
                spacing: T.s4

                RowLayout {
                    spacing: T.s8
                    Layout.bottomMargin: T.s16
                    Layout.leftMargin: T.s8
                    Icon { name: "cat"; size: 24; color: theme.accent }
                    Label { text: "Catwatch"; font.pixelSize: T.title; font.weight: Font.Bold; color: T.moon }
                }

                Repeater {
                    model: win.pages
                    AbstractButton {
                        id: nav
                        readonly property bool on: win.current === index
                        Layout.fillWidth: true
                        implicitHeight: T.s32 + T.s8
                        hoverEnabled: true
                        focusPolicy: Qt.StrongFocus
                        onClicked: win.current = index
                        Accessible.name: modelData.title
                        background: Rectangle {
                            radius: T.r4
                            color: nav.on ? T.haze : nav.hovered ? Qt.rgba(T.haze.r, T.haze.g, T.haze.b, .5) : "transparent"
                            border.width: nav.visualFocus ? 1 : 0; border.color: T.fog
                            Rectangle { visible: nav.on; width: T.s2; height: T.s16; radius: T.r2; color: theme.accent
                                anchors.verticalCenter: parent.verticalCenter }
                        }
                        contentItem: RowLayout {
                            spacing: T.s16
                            Item { implicitWidth: T.s2 }
                            Icon { name: modelData.icon; size: 20; color: nav.on ? theme.accent : T.fog }
                            Label { text: modelData.title; color: nav.on ? T.moon : T.fog; font.weight: nav.on ? Font.DemiBold : Font.Normal; Layout.fillWidth: true }
                            Label { text: String(index + 1); color: T.seam; font.pixelSize: T.caption }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // Estado do servidor deste PC e da conexão.
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: T.seam }
                RowLayout {
                    Layout.topMargin: T.s8
                    spacing: T.s8
                    Rectangle {
                        implicitWidth: T.s8; implicitHeight: T.s8; radius: T.r4
                        color: server.state === "running" || server.state === "external" ? T.ok
                             : server.state === "error" ? T.alert : server.state === "stopped" ? T.fog : T.warn
                    }
                    Label {
                        text: ({ running: "Servidor rodando", external: "Servidor rodando", starting: "Servidor iniciando",
                                 stopping: "Servidor parando", error: "Erro no servidor",
                                 stopped: backend.isLocal ? "Servidor parado" : "Servidor de outro PC" })[server.state] || ""
                        color: T.moon; font.pixelSize: T.caption; Layout.fillWidth: true
                    }
                }
                Label { text: backend.serverUrl.replace(/^https?:\/\//, ""); color: T.fog; font.pixelSize: T.caption; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { visible: backend.error !== ""; text: backend.error; color: T.alert; font.pixelSize: T.caption; wrapMode: Text.Wrap; Layout.fillWidth: true }
                ActionButton { text: "Desconectar"; icon_: "lan-disconnect"; Layout.fillWidth: true; Layout.topMargin: T.s4; onClicked: backend.disconnectServer() }

                // Aparência: automático (segue o sistema), claro ou escuro.
                RowLayout {
                    Layout.topMargin: T.s8
                    spacing: T.s4
                    Label { text: "Aparência"; color: T.fog; font.pixelSize: T.caption; Layout.fillWidth: true }
                    Repeater {
                        model: [{ m: "auto", i: "brightness-auto", t: "Automático: segue o tema do sistema" },
                                { m: "light", i: "white-balance-sunny", t: "Claro" }, { m: "dark", i: "weather-night", t: "Escuro" }]
                        IconButton { icon_: modelData.i; tip: modelData.t; selected: shell.themeMode === modelData.m; onClicked: shell.themeMode = modelData.m }
                    }
                }
            }
        }

        StackLayout {
            currentIndex: win.current
            Layout.fillWidth: true
            Layout.fillHeight: true
            TodayPage { app: win }
            CamerasPage { app: win; active: win.current === 1 }
            CatsPage { app: win; active: win.current === 2 }
            HistoryPage { app: win; active: win.current === 3 }
            ServerPage { app: win; active: win.current === 4 }
        }
    }

    // ---------- Atalhos ----------
    Rectangle {
        anchors.fill: parent
        z: 200
        visible: win.helpVisible
        color: T.scrim
        MouseArea { anchors.fill: parent; onClicked: win.helpVisible = false }
        Panel {
            anchors.centerIn: parent
            width: 416
            title: "Atalhos"
            Repeater {
                model: [["1 a 5", "Hoje, Câmeras, Gatos, Histórico, Servidor"], ["R", "Atualizar"], ["?", "Mostrar ou esconder esta ajuda"], ["Q", "Sair"]]
                RowLayout {
                    spacing: T.s16
                    Rectangle {
                        implicitWidth: Math.max(T.s32 + T.s16, keyLabel.implicitWidth + T.s16); implicitHeight: 24
                        radius: T.r4; color: T.haze; border.width: 1; border.color: T.seam
                        Label { id: keyLabel; anchors.centerIn: parent; text: modelData[0]; color: T.moon; font.pixelSize: T.caption }
                    }
                    Label { text: modelData[1]; color: T.fog }
                }
            }
        }
    }
}
