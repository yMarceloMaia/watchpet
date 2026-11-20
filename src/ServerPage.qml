import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts

// Aba "Servidor": liga/desliga o servidor deste PC, conecta o celular, mostra o uso,
// as configurações, os dados e o log ao vivo.
Flickable {
    id: page
    contentHeight: col.height + 32
    clip: true
    ScrollBar.vertical: ScrollBar {}

    // Vêm do Main.qml: se esta aba está visível e como pedir confirmação.
    property bool active: false
    property var ask: function (text, action) { action() }

    readonly property bool serverOn: server.state === "running" || server.state === "external"
    readonly property var st: backend.status
    property bool showToken: false
    property bool showOutput: false

    readonly property var stateText: ({
        stopped: "Parado", starting: "Iniciando", running: "Rodando", external: "Rodando (aberto fora do app)",
        stopping: "Encerrando", error: "Erro"
    })
    readonly property var stateColor: ({
        stopped: "#8e8e93", starting: "#ff9f0a", running: "#30d158", external: "#30d158", stopping: "#ff9f0a", error: "#ff453a"
    })
    readonly property var eventIcon: ({
        visit: "🐾", alert: "⚠️", camera_offline: "📷", camera_online: "📷", server: "🖥️", error: "❌"
    })

    function duration(sec) {
        sec = Math.floor(sec || 0)
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
        return d ? d + " d " + h + " h" : h ? h + " h " + m + " min" : m + " min"
    }
    function num(v, digits) { return v === undefined || v === null ? "—" : Number(v).toFixed(digits) }

    // Um cartão com título; o conteúdo vai empilhado dentro.
    component Section: Rectangle {
        default property alias content: inner.data
        property string title
        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + 28
        color: "#1b1b1f"; radius: theme.radius
        ColumnLayout {
            id: inner
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 8
            Label { text: parent.parent.title; font.bold: true; font.pixelSize: 16 }
        }
    }
    // Linha "rótulo .... valor" das informações de uso.
    component Info: RowLayout {
        property string label
        property string value
        Layout.fillWidth: true
        Label { text: parent.label; opacity: .6; Layout.preferredWidth: 240 }
        Label { text: parent.value; Layout.fillWidth: true; elide: Text.ElideMiddle }
    }
    // Campo numérico com rótulo e unidade.
    component Num: RowLayout {
        property alias value: spin.value
        property alias from: spin.from
        property alias to: spin.to
        property string label
        property string unit
        Layout.fillWidth: true
        Label { text: parent.label; Layout.preferredWidth: 260; wrapMode: Text.Wrap }
        SpinBox {
            id: spin
            editable: true
            Layout.preferredWidth: 150
            // Números crus: "8000", não "8.000" (porta e horas não levam separador de milhar).
            textFromValue: (v, locale) => String(v)
            valueFromText: (t, locale) => parseInt(t) || 0
        }
        Label { text: parent.unit; opacity: .6; Layout.fillWidth: true }
    }

    FolderDialog {
        id: folderDialog
        title: "Pasta do servidor Catwatch"
        onAccepted: server.setServerDirUrl(selectedFolder.toString())
    }
    FileDialog {
        id: saveDialog
        property string path
        fileMode: FileDialog.SaveFile
        currentFolder: StandardPaths.standardLocations(StandardPaths.DownloadLocation)[0]
        onAccepted: backend.download(path, selectedFile.toString())
    }
    function saveAs(path, name, filter) {
        saveDialog.path = path
        saveDialog.nameFilters = [filter]
        saveDialog.selectedFile = saveDialog.currentFolder + "/" + name
        saveDialog.open()
    }

    ColumnLayout {
        id: col
        x: 16; y: 16
        width: Math.min(parent.width - 32, 980)
        spacing: 12

        // ===== Servidor deste PC =====
        Section {
            title: "Servidor deste PC"
            RowLayout {
                spacing: 10
                Rectangle { width: 12; height: 12; radius: 6; color: page.stateColor[server.state] || "#8e8e93" }
                Label { text: page.stateText[server.state] || server.state; font.bold: true }
                BusyIndicator { running: server.state === "starting" || server.state === "stopping"; visible: running; implicitWidth: 28; implicitHeight: 28 }
                Label { text: server.message; opacity: .7; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Button { text: "Iniciar"; highlighted: true; enabled: server.state === "stopped" || server.state === "error"; onClicked: server.start() }
                Button { text: "Parar"; enabled: page.serverOn || server.state === "starting"
                    onClicked: page.ask("Parar o servidor? As câmeras deixam de ser monitoradas até você iniciar de novo.", () => server.stop()) }
                Button { text: "Reiniciar"; enabled: page.serverOn; onClicked: server.restart() }
                Button { text: "Abrir painel web"; flat: true; enabled: page.serverOn; onClicked: Qt.openUrlExternally(server.localUrl()) }
            }
            Label {
                visible: page.st.restart_required === true && page.serverOn
                text: "⚠️ Há configurações que só valem depois de reiniciar o servidor."
                color: "#ff9f0a"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    Layout.fillWidth: true
                    readOnly: true
                    text: server.serverDir
                    placeholderText: "Pasta do servidor (projeto pet, com catwatch/ e .venv)"
                }
                Button { text: "Escolher…"; onClicked: folderDialog.open() }
            }
            Label {
                visible: !server.serverDirValid
                text: "Essa pasta não tem o servidor: precisa ter catwatch/ e o ambiente .venv instalado."
                color: "#ff453a"; wrapMode: Text.Wrap; Layout.fillWidth: true
            }
            Switch { text: "Iniciar o servidor quando o app abrir"; checked: server.autoStart; onToggled: server.autoStart = checked }
            Switch {
                text: shell.trayAvailable ? "Ao fechar a janela, continuar rodando na bandeja"
                                          : "Ao fechar a janela, continuar rodando (bandeja indisponível neste sistema)"
                enabled: shell.trayAvailable
                checked: shell.runInBackground
                onToggled: shell.runInBackground = checked
            }
            Switch { text: "Iniciar com o sistema (abre direto na bandeja e liga o servidor)"; checked: shell.startWithSystem; onToggled: shell.startWithSystem = checked }
        }

        // ===== Celular =====
        Section {
            title: "Conectar o celular"
            visible: backend.connected
            RowLayout {
                spacing: 16
                Rectangle {
                    Layout.preferredWidth: 196; Layout.preferredHeight: 196
                    color: "white"; radius: theme.radius
                    Image {
                        anchors.fill: parent; anchors.margins: 6
                        fillMode: Image.PreserveAspectFit
                        cache: false
                        smooth: false  // QR nítido
                        source: page.active && backend.connected ? backend.pairQrUrl(backend.pairRevision) : ""
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Label { text: "No app do celular, toque em “Ler QR code” e aponte para cá."; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label { text: "Ou digite um destes endereços:"; opacity: .6 }
                    Repeater {
                        model: backend.pair.urls || []
                        Label { text: "• " + modelData; font.family: "monospace" }
                    }
                    RowLayout {
                        Label { text: "Token:"; opacity: .6 }
                        Label { text: page.showToken ? backend.token : "••••••••••••"; font.family: "monospace" }
                        ToolButton { text: page.showToken ? "Ocultar" : "Mostrar"; onClicked: page.showToken = !page.showToken }
                    }
                    Button {
                        text: "Gerar novo token"
                        flat: true
                        Material.foreground: "#ff453a"
                        onClicked: page.ask("Gerar um token novo? Celulares e outros PCs conectados precisarão conectar de novo (pelo QR code).", () => backend.regenerateToken())
                    }
                }
            }
        }

        // ===== Uso =====
        Section {
            title: "Uso do servidor"
            visible: backend.connected
            Info { label: "Processamento"; value: page.st.device === "cuda" ? "Placa de vídeo — " + (page.st.gpu || "") : page.st.device === "cpu" ? "CPU" : "—" }
            Info { label: "Tempo de análise por quadro"; value: page.st.frames_analyzed ? page.num(page.st.infer_ms, 0) + " ms" : "ainda sem quadros" }
            Info { label: "CPU do servidor"; value: page.num(page.st.cpu_percent, 1) + " %" }
            Info { label: "Memória"; value: page.num(page.st.ram_mb, 0) + " MB" + (page.st.gpu_memory_mb ? "  ·  placa de vídeo " + page.num(page.st.gpu_memory_mb, 0) + " MB" : "") }
            Info { label: "Câmeras online"; value: (page.st.cameras_online ?? "—") + " de " + (page.st.cameras_total ?? "—") }
            Info { label: "Gatos cadastrados"; value: String(page.st.cats ?? "—") }
            Info { label: "Visitas hoje"; value: String(page.st.visits_today ?? "—") }
            Info { label: "Ligado há"; value: page.st.uptime ? page.duration(page.st.uptime) : "—" }
            Info { label: "Pasta de dados"; value: page.st.data_dir || "—" }
        }

        // ===== Configurações =====
        Section {
            id: settingsSection
            title: "Configurações"
            visible: backend.connected

            function load() {
                const s = backend.settings
                if (!s.detection) return
                fps.value = s.detection.fps
                conf.value = Math.round(s.detection.confidence * 100)
                thr.value = Math.round(s.detection.identify_threshold * 100)
                device.currentIndex = Math.max(0, ["auto", "cpu", "cuda"].indexOf(s.detection.device))
                minSec.value = s.visits.min_seconds
                gapSec.value = s.visits.gap_seconds
                alertsOn.checked = s.alerts.enabled
                offMin.value = s.alerts.camera_offline_minutes
                waterH.value = s.alerts.water_by_hour
                foodH.value = s.alerts.food_by_hour
                litterH.value = s.alerts.litter_max_hours
                spike.value = Math.round(s.alerts.litter_spike_factor * 10)
                port.value = s.server.port
            }
            Connections { target: backend; function onSettingsChanged() { settingsSection.load() } }
            Component.onCompleted: load()

            Label { text: "Detecção"; opacity: .6; Layout.topMargin: 4 }
            Num { id: fps; label: "Quadros analisados por segundo (por câmera)"; from: 1; to: 15; unit: "mais = detecta melhor, usa mais processamento" }
            Num { id: conf; label: "Confiança mínima para ver um gato"; from: 10; to: 95; unit: "%" }
            Num { id: thr; label: "Similaridade mínima para dar nome ao gato"; from: 30; to: 99; unit: "% — abaixo disso vira “desconhecido”" }
            RowLayout {
                Label { text: "Processador"; Layout.preferredWidth: 260 }
                ComboBox {
                    id: device
                    Layout.preferredWidth: 220
                    textRole: "text"; valueRole: "value"
                    model: [{ text: "Automático", value: "auto" }, { text: "CPU", value: "cpu" }, { text: "Placa de vídeo (NVIDIA)", value: "cuda" }]
                }
                Label { text: "requer reiniciar"; opacity: .6 }
            }

            Label { text: "Visitas"; opacity: .6; Layout.topMargin: 8 }
            Num { id: minSec; label: "Tempo mínimo na zona para contar"; from: 1; to: 120; unit: "segundos" }
            Num { id: gapSec; label: "Encerrar a visita depois de não ver o gato por"; from: 2; to: 300; unit: "segundos" }

            Label { text: "Alertas"; opacity: .6; Layout.topMargin: 8 }
            Switch { id: alertsOn; text: "Avisar sobre comportamento dos gatos" }
            Num { id: waterH; label: "Avisar se não bebeu água até as"; from: 0; to: 23; unit: "horas"; enabled: alertsOn.checked }
            Num { id: foodH; label: "Avisar se não comeu até as"; from: 0; to: 23; unit: "horas"; enabled: alertsOn.checked }
            Num { id: litterH; label: "Avisar se não foi à caixa por mais de"; from: 4; to: 96; unit: "horas"; enabled: alertsOn.checked }
            Num { id: spike; label: "Avisar se as idas à caixa no dia passarem de"; from: 12; to: 100; unit: "÷10 × a média da semana (20 = o dobro)"; enabled: alertsOn.checked }
            Num { id: offMin; label: "Avisar quando uma câmera ficar sem imagem por"; from: 1; to: 240; unit: "minutos" }

            Label { text: "Notificações neste PC"; opacity: .6; Layout.topMargin: 8 }
            Switch { text: "Notificar alertas e câmeras fora do ar"; checked: shell.notifyAlerts; onToggled: shell.notifyAlerts = checked }
            Switch { text: "Notificar cada visita"; checked: shell.notifyVisits; onToggled: shell.notifyVisits = checked }

            Label { text: "Rede"; opacity: .6; Layout.topMargin: 8 }
            Num { id: port; label: "Porta do servidor"; from: 1024; to: 65535; unit: "requer reiniciar" }

            RowLayout {
                Layout.topMargin: 8
                Button {
                    text: "Salvar configurações"; highlighted: true
                    onClicked: backend.saveSettings({
                        detection: { fps: fps.value, confidence: conf.value / 100, identify_threshold: thr.value / 100, device: device.currentValue },
                        visits: { min_seconds: minSec.value, gap_seconds: gapSec.value },
                        alerts: { enabled: alertsOn.checked, camera_offline_minutes: offMin.value, water_by_hour: waterH.value,
                                  food_by_hour: foodH.value, litter_max_hours: litterH.value, litter_spike_factor: spike.value / 10 },
                        server: { port: port.value }
                    })
                }
                Button { text: "Desfazer"; flat: true; onClicked: settingsSection.load() }
            }
        }

        // ===== Dados =====
        Section {
            title: "Dados"
            visible: backend.connected
            Label { text: "As fotos e o histórico ficam no servidor. Guarde um backup de vez em quando."; opacity: .6; wrapMode: Text.Wrap; Layout.fillWidth: true }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Button { text: "Exportar visitas (CSV)"; enabled: !backend.downloading
                    onClicked: page.saveAs("/api/export/visits.csv", "catwatch-visitas.csv", "Planilha CSV (*.csv)") }
                Button { text: "Backup completo (.zip)"; enabled: !backend.downloading
                    onClicked: page.saveAs("/api/backup.zip", "catwatch-backup-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmm") + ".zip", "Arquivo ZIP (*.zip)") }
            }
            ProgressBar {
                visible: backend.downloading
                Layout.fillWidth: true
                indeterminate: backend.downloadProgress < 0
                from: 0; to: 100; value: Math.max(0, backend.downloadProgress)
            }
        }

        // ===== Log =====
        Section {
            title: "Log ao vivo"
            visible: backend.connected || server.output !== ""
            ListView {
                id: log
                visible: backend.connected
                Layout.fillWidth: true
                Layout.preferredHeight: 300
                clip: true
                model: backend.events
                ScrollBar.vertical: ScrollBar {}
                Label { anchors.centerIn: parent; visible: log.count === 0; text: "Sem eventos ainda."; opacity: .6 }
                delegate: RowLayout {
                    width: ListView.view.width - 12
                    spacing: 8
                    Label { text: new Date(modelData.ts * 1000).toLocaleString(Qt.locale(), "dd/MM HH:mm:ss"); opacity: .5; font.family: "monospace"; font.pixelSize: 12 }
                    Label { text: page.eventIcon[modelData.type] || "•" }
                    Label {
                        text: modelData.message
                        color: modelData.level === "error" ? "#ff453a" : modelData.level === "warn" ? "#ff9f0a" : "#e5e5ea"
                        Layout.fillWidth: true; elide: Text.ElideRight
                    }
                }
            }
            Switch { text: "Mostrar a saída do processo do servidor"; checked: page.showOutput; onToggled: page.showOutput = checked; visible: server.output !== "" }
            ScrollView {
                visible: page.showOutput && server.output !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: 240
                TextArea {
                    readOnly: true
                    text: server.output
                    font.family: "monospace"; font.pixelSize: 12
                    wrapMode: TextEdit.NoWrap
                    onTextChanged: cursorPosition = length  // acompanha o fim, como um terminal
                }
            }
        }
    }
}
