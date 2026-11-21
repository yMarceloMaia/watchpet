import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts
import "."

// Servidor: liga e desliga o servidor deste PC, conecta o celular, mostra o uso,
// as configurações, os dados e o log. Em tela larga, duas colunas.
Flickable {
    id: page
    property var app
    property bool active: false
    contentHeight: col.implicitHeight + T.s64
    clip: true
    ScrollBar.vertical: ScrollBar {}

    readonly property bool serverOn: server.state === "running" || server.state === "external"
    readonly property var st: backend.status
    readonly property bool wide: col.width >= 1120
    property bool showToken: false
    property bool showOutput: false

    readonly property var stateText: ({
        stopped: "Parado", starting: "Iniciando", running: "Rodando", external: "Rodando, aberto fora do app",
        stopping: "Encerrando", error: "Com erro"
    })
    readonly property var stateColor: ({
        stopped: T.fog, starting: T.warn, running: T.ok, external: T.ok, stopping: T.warn, error: T.alert
    })
    readonly property var eventIcon: ({
        visit: "paw", alert: "alert-circle", camera_offline: "cctv", camera_online: "cctv", server: "server", error: "alert"
    })

    function duration(sec) {
        sec = Math.floor(sec || 0)
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
        return d ? d + " d " + h + " h" : h ? h + " h " + m + " min" : m + " min"
    }
    function num(v, digits) { return v === undefined || v === null ? "—" : Number(v).toLocaleString(T.locale, "f", digits) }

    // Linha "rótulo  valor" do painel de uso.
    component Info: RowLayout {
        property string label
        property string value
        Layout.fillWidth: true
        spacing: T.s16
        Label { text: parent.label; color: T.fog; Layout.preferredWidth: 192 }
        Label { text: parent.value; color: T.moon; font.features: { "tnum": 1 }; Layout.fillWidth: true; elide: Text.ElideMiddle }
    }
    // Campo numérico com rótulo e unidade.
    component Num: RowLayout {
        property alias value: spin.value
        property alias from: spin.from
        property alias to: spin.to
        property string label
        property string unit
        Layout.fillWidth: true
        spacing: T.s16
        Label { text: parent.label; color: T.moon; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SpinBox {
            id: spin
            editable: true
            Layout.preferredWidth: 144
            // Números crus: "8000", não "8.000".
            textFromValue: (v, locale) => String(v)
            valueFromText: (t, locale) => parseInt(t) || 0
        }
        Label { text: parent.unit; color: T.fog; font.pixelSize: T.caption; wrapMode: Text.Wrap; Layout.preferredWidth: 128 }
    }
    // Regra de um tipo de zona: quanto o gato precisa ficar e quanto tempo sumido encerra a visita.
    component KindRule: RowLayout {
        id: rule
        property string kind
        property alias minValue: minSpin.value
        property alias gapValue: gapSpin.value
        Layout.fillWidth: true
        spacing: T.s16
        // Um layout aninhado não se estica sozinho; o Item ocupa a coluna e a marca fica dentro.
        Item {
            Layout.fillWidth: true
            implicitHeight: tag.implicitHeight
            KindTag { id: tag; kind: rule.kind; anchors.verticalCenter: parent.verticalCenter }
        }
        SpinBox { id: minSpin; from: 1; to: 600; editable: true; Layout.preferredWidth: 144
            textFromValue: (v, l) => String(v); valueFromText: (t, l) => parseInt(t) || 0 }
        SpinBox { id: gapSpin; from: 2; to: 600; editable: true; Layout.preferredWidth: 144
            textFromValue: (v, l) => String(v); valueFromText: (t, l) => parseInt(t) || 0 }
        Item { Layout.preferredWidth: 128 - T.s16 * 2 }
    }
    component Group: Label { color: T.fog; font.pixelSize: T.caption; font.weight: Font.Medium; Layout.topMargin: T.s8 }

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
    FileDialog {
        id: importDialog
        title: "Importar backup do Catwatch"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Backup do Catwatch (*.zip)"]
        currentFolder: StandardPaths.standardLocations(StandardPaths.DownloadLocation)[0]
        onAccepted: {
            const file = selectedFile.toString()
            const withSettings = importSettings.checked
            page.app.ask("Importar este backup? Os gatos, o histórico e as fotos deste servidor"
                         + (withSettings ? ", as câmeras, as zonas e as configurações" : "")
                         + " serão substituídos pelos do backup. Antes, o servidor guarda uma cópia do que existe hoje em data/backups.",
                         () => backend.importBackup(file, withSettings))
        }
    }
    function saveAs(path, name, filter) {
        saveDialog.path = path
        saveDialog.nameFilters = [filter]
        saveDialog.selectedFile = saveDialog.currentFolder + "/" + name
        saveDialog.open()
    }

    ColumnLayout {
        id: col
        x: T.s32; y: T.s32
        width: page.width - T.s64
        spacing: T.s16

        PageHeader {
            title: "Servidor"
            subtitle: "O servidor é quem olha as câmeras e reconhece os gatos. Ele precisa estar rodando para o monitoramento funcionar."
        }

        GridLayout {
            Layout.fillWidth: true
            columns: page.wide ? 2 : 1
            columnSpacing: T.s16; rowSpacing: T.s16

            // ===== Coluna 1: controle, celular, uso =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: T.s16

                Panel {
                    Layout.fillWidth: true
                    title: "Servidor deste PC"
                    RowLayout {
                        spacing: T.s8
                        Layout.fillWidth: true
                        Rectangle { width: T.s8; height: T.s8; radius: T.r4; color: page.stateColor[server.state] || T.fog }
                        Label { text: page.stateText[server.state] || server.state; color: T.moon; font.pixelSize: T.strong; font.weight: Font.DemiBold }
                        BusyIndicator { running: server.state === "starting" || server.state === "stopping"; visible: running; implicitWidth: 24; implicitHeight: 24 }
                        Label { text: server.message; color: server.state === "error" ? T.alert : T.fog; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                    Label {
                        visible: page.st.restart_required === true && page.serverOn
                        text: "Algumas configurações só valem depois de reiniciar o servidor."
                        color: T.warn; wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: T.s8
                        ActionButton { text: "Iniciar"; icon_: "play"; primary: true; enabled: server.state === "stopped" || server.state === "error"; onClicked: server.start() }
                        ActionButton { text: "Parar"; icon_: "stop"; enabled: page.serverOn || server.state === "starting"
                            onClicked: page.app.ask("Parar o servidor? As câmeras deixam de ser monitoradas até você iniciar de novo.", () => server.stop()) }
                        ActionButton { text: "Reiniciar"; icon_: "restart"; enabled: page.serverOn; onClicked: server.restart() }
                        ActionButton { text: "Painel web"; icon_: "web"; enabled: page.serverOn; onClicked: Qt.openUrlExternally(server.localUrl()) }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: T.seam; Layout.topMargin: T.s8 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: T.s8
                        TextField {
                            Layout.fillWidth: true
                            readOnly: true
                            text: server.serverDir
                            placeholderText: "Pasta do servidor (com catwatch/ e .venv)"
                        }
                        ActionButton { text: "Escolher"; icon_: "folder-open"; onClicked: folderDialog.open() }
                    }
                    Label {
                        visible: !server.serverDirValid
                        text: "Essa pasta não tem o servidor. Ela precisa ter catwatch/ e o ambiente .venv instalado."
                        color: T.alert; wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                    Switch { text: "Iniciar o servidor quando o app abrir"; checked: server.autoStart; onToggled: server.autoStart = checked }
                    Switch {
                        text: shell.trayAvailable ? "Ao fechar a janela, continuar na bandeja" : "Ao fechar a janela, continuar rodando (sem bandeja neste sistema)"
                        enabled: shell.trayAvailable
                        checked: shell.runInBackground
                        onToggled: shell.runInBackground = checked
                    }
                    Switch { text: "Iniciar com o sistema, já na bandeja"; checked: shell.startWithSystem; onToggled: shell.startWithSystem = checked }
                }

                Panel {
                    visible: backend.connected
                    Layout.fillWidth: true
                    title: "Conectar o celular"
                    subtitle: "No app do celular, toque em Ler QR code e aponte para o código."
                    RowLayout {
                        spacing: T.s16
                        Layout.fillWidth: true
                        Rectangle {
                            Layout.preferredWidth: 192; Layout.preferredHeight: 192
                            Layout.alignment: Qt.AlignTop
                            color: "white"; radius: T.r4
                            Image {
                                anchors.fill: parent; anchors.margins: T.s8
                                fillMode: Image.PreserveAspectFit
                                cache: false
                                smooth: false  // QR nítido
                                source: page.active && backend.connected ? backend.pairQrUrl(backend.pairRevision) : ""
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: T.s8
                            Label { text: "Ou digite um destes endereços"; color: T.fog; font.pixelSize: T.caption }
                            Repeater {
                                model: backend.pair.urls || []
                                Label { text: modelData; color: T.moon; font.features: { "tnum": 1 } }
                            }
                            Label { text: "e o token"; color: T.fog; font.pixelSize: T.caption; Layout.topMargin: T.s8 }
                            RowLayout {
                                spacing: T.s4
                                Label { text: page.showToken ? backend.token : "••••••••••••"; color: T.moon }
                                IconButton { icon_: page.showToken ? "eye-off" : "eye"; tip: page.showToken ? "Ocultar o token" : "Mostrar o token"
                                    onClicked: page.showToken = !page.showToken }
                            }
                            ActionButton {
                                Layout.topMargin: T.s8
                                text: "Gerar novo token"; icon_: "refresh"; tint: T.alert
                                onClicked: page.app.ask("Gerar um token novo? Celulares e outros PCs conectados precisarão ler o QR code de novo.", () => backend.regenerateToken())
                            }
                        }
                    }
                }

                Panel {
                    visible: backend.connected
                    Layout.fillWidth: true
                    title: "Uso"
                    Info { label: "Processamento"; value: page.st.device === "cuda" ? "Placa de vídeo, " + (page.st.gpu || "") : page.st.device === "cpu" ? "CPU" : "—" }
                    Info { label: "Análise por quadro"; value: page.st.frames_analyzed ? page.num(page.st.infer_ms, 0) + " ms" : "aguardando o primeiro quadro" }
                    Info { label: "CPU do servidor"; value: page.num(page.st.cpu_percent, 1) + " %" }
                    Info { label: "Memória"; value: page.num(page.st.ram_mb, 0) + " MB" + (page.st.gpu_memory_mb ? ", placa de vídeo " + page.num(page.st.gpu_memory_mb, 0) + " MB" : "") }
                    Info { label: "Câmeras com imagem"; value: (page.st.cameras_online ?? "—") + " de " + (page.st.cameras_total ?? "—") }
                    Info { label: "Gatos cadastrados"; value: String(page.st.cats ?? "—") }
                    Info { label: "Visitas hoje"; value: String(page.st.visits_today ?? "—") }
                    Info { label: "Ligado há"; value: page.st.uptime ? page.duration(page.st.uptime) : "—" }
                    Info { label: "Pasta de dados"; value: page.st.data_dir || "—" }
                }
            }

            // ===== Coluna 2: configurações, dados, log =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: T.s16

                Panel {
                    id: settingsPanel
                    visible: backend.connected
                    Layout.fillWidth: true
                    title: "Configurações"

                    function load() {
                        const s = backend.settings
                        if (!s.detection) return
                        fps.value = s.detection.fps
                        conf.value = Math.round(s.detection.confidence * 100)
                        thr.value = Math.round(s.detection.identify_threshold * 100)
                        device.currentIndex = Math.max(0, ["auto", "cpu", "cuda"].indexOf(s.detection.device))
                        for (const [rule, k] of [[ruleLitter, "litter"], [ruleFood, "food"], [ruleWater, "water"]]) {
                            rule.minValue = s.visits["min_" + k]
                            rule.gapValue = s.visits["gap_" + k]
                        }
                        alertsOn.checked = s.alerts.enabled
                        offMin.value = s.alerts.camera_offline_minutes
                        waterH.value = s.alerts.water_by_hour
                        foodH.value = s.alerts.food_by_hour
                        litterH.value = s.alerts.litter_max_hours
                        spike.value = Math.round(s.alerts.litter_spike_factor * 10)
                        port.value = s.server.port
                    }
                    Connections { target: backend; function onSettingsChanged() { settingsPanel.load() } }
                    Component.onCompleted: load()

                    Group { text: "Detecção"; Layout.topMargin: 0 }
                    Num { id: fps; label: "Quadros analisados por segundo"; from: 1; to: 15; unit: "por câmera" }
                    Num { id: conf; label: "Confiança mínima para ver um gato"; from: 10; to: 95; unit: "%" }
                    Num { id: thr; label: "Similaridade mínima para dar nome"; from: 30; to: 99; unit: "% (abaixo: desconhecido)" }
                    RowLayout {
                        spacing: T.s16
                        Label { text: "Processador"; color: T.moon; Layout.fillWidth: true }
                        ComboBox {
                            id: device
                            Layout.preferredWidth: 144
                            textRole: "text"; valueRole: "value"
                            model: [{ text: "Automático", value: "auto" }, { text: "CPU", value: "cpu" }, { text: "NVIDIA", value: "cuda" }]
                        }
                        Label { text: "vale ao reiniciar"; color: T.fog; font.pixelSize: T.caption; Layout.preferredWidth: 128 }
                    }

                    Group { text: "Visitas" }
                    Label {
                        text: "Uma visita só conta se o mesmo gato ficar na zona pelo tempo mínimo. Passadas rápidas não contam. "
                              + "A visita acaba depois de um tempo sem ver o gato; na caixa ele some ao se agachar."
                        color: T.fog; font.pixelSize: T.caption; wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: T.s16
                        Item { Layout.fillWidth: true }
                        Label { text: "Ficar ao menos (s)"; color: T.fog; font.pixelSize: T.caption; Layout.preferredWidth: 144 }
                        Label { text: "Encerrar sem ver por (s)"; color: T.fog; font.pixelSize: T.caption; Layout.preferredWidth: 144 }
                        Item { Layout.preferredWidth: 128 - T.s16 * 2 }
                    }
                    KindRule { id: ruleLitter; kind: "litter" }
                    KindRule { id: ruleFood; kind: "food" }
                    KindRule { id: ruleWater; kind: "water" }

                    Group { text: "Alertas" }
                    Switch { id: alertsOn; text: "Avisar sobre o comportamento dos gatos" }
                    Num { id: waterH; label: "Sem beber água até as"; from: 0; to: 23; unit: "horas"; enabled: alertsOn.checked }
                    Num { id: foodH; label: "Sem comer até as"; from: 0; to: 23; unit: "horas"; enabled: alertsOn.checked }
                    Num { id: litterH; label: "Sem ir à caixa por mais de"; from: 4; to: 96; unit: "horas"; enabled: alertsOn.checked }
                    Num { id: spike; label: "Idas à caixa no dia acima de"; from: 12; to: 100; unit: "÷10 da média; 20 = o dobro"; enabled: alertsOn.checked }
                    Num { id: offMin; label: "Câmera sem imagem por"; from: 1; to: 240; unit: "minutos" }

                    Group { text: "Notificações neste PC" }
                    Switch { text: "Alertas e câmeras sem imagem"; checked: shell.notifyAlerts; onToggled: shell.notifyAlerts = checked }
                    Switch { text: "Cada visita"; checked: shell.notifyVisits; onToggled: shell.notifyVisits = checked }

                    Group { text: "Rede" }
                    Num { id: port; label: "Porta do servidor"; from: 1024; to: 65535; unit: "vale ao reiniciar" }

                    RowLayout {
                        Layout.topMargin: T.s8
                        spacing: T.s8
                        ActionButton {
                            text: "Salvar configurações"; icon_: "content-save"; primary: true
                            onClicked: backend.saveSettings({
                                detection: { fps: fps.value, confidence: conf.value / 100, identify_threshold: thr.value / 100, device: device.currentValue },
                                visits: { min_litter: ruleLitter.minValue, min_food: ruleFood.minValue, min_water: ruleWater.minValue,
                                          gap_litter: ruleLitter.gapValue, gap_food: ruleFood.gapValue, gap_water: ruleWater.gapValue },
                                alerts: { enabled: alertsOn.checked, camera_offline_minutes: offMin.value, water_by_hour: waterH.value,
                                          food_by_hour: foodH.value, litter_max_hours: litterH.value, litter_spike_factor: spike.value / 10 },
                                server: { port: port.value }
                            })
                        }
                        ActionButton { text: "Desfazer"; icon_: "restart"; onClicked: settingsPanel.load() }
                    }
                }

                Panel {
                    visible: backend.connected
                    Layout.fillWidth: true
                    title: "Dados"
                    subtitle: "O histórico e as fotos ficam no servidor. Guarde um backup de vez em quando; com ele você leva tudo para outro PC ou volta atrás."
                    Flow {
                        Layout.fillWidth: true
                        spacing: T.s8
                        ActionButton { text: "Exportar visitas (CSV)"; icon_: "download"; enabled: !backend.downloading
                            onClicked: page.saveAs("/api/export/visits.csv", "catwatch-visitas.csv", "Planilha CSV (*.csv)") }
                        ActionButton { text: "Backup completo (.zip)"; icon_: "download"; enabled: !backend.downloading && !backend.importing
                            onClicked: page.saveAs("/api/backup.zip", "catwatch-backup-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmm") + ".zip", "Arquivo ZIP (*.zip)") }
                        ActionButton { text: "Importar backup (.zip)"; icon_: "upload"; enabled: !backend.downloading && !backend.importing
                            onClicked: importDialog.open() }
                    }
                    Switch {
                        id: importSettings
                        checked: true
                        text: "Ao importar, trazer também câmeras, zonas e configurações"
                    }
                    ProgressBar {
                        visible: backend.downloading
                        Layout.fillWidth: true
                        indeterminate: backend.downloadProgress < 0
                        from: 0; to: 100; value: Math.max(0, backend.downloadProgress)
                    }
                    ColumnLayout {
                        visible: backend.importing
                        Layout.fillWidth: true
                        spacing: T.s4
                        Label {
                            text: backend.importProgress >= 0 ? "Enviando o backup ao servidor" : "Importando: o servidor está trocando os dados e reanalisando as fotos dos gatos"
                            color: T.fog; font.pixelSize: T.caption; wrapMode: Text.Wrap; Layout.fillWidth: true
                        }
                        ProgressBar {
                            Layout.fillWidth: true
                            indeterminate: backend.importProgress < 0
                            from: 0; to: 100; value: Math.max(0, backend.importProgress)
                        }
                    }
                }

                Panel {
                    visible: backend.connected || server.output !== ""
                    Layout.fillWidth: true
                    title: "Log ao vivo"
                    ListView {
                        id: log
                        visible: backend.connected
                        Layout.fillWidth: true
                        Layout.preferredHeight: 320
                        clip: true
                        spacing: T.s4
                        model: backend.events
                        ScrollBar.vertical: ScrollBar {}
                        Label { anchors.centerIn: parent; visible: log.count === 0; text: "Sem eventos ainda."; color: T.fog }
                        delegate: RowLayout {
                            width: ListView.view.width - T.s16
                            spacing: T.s8
                            Label { text: new Date(modelData.ts * 1000).toLocaleString(T.locale, "dd/MM HH:mm:ss"); color: T.fog; font.pixelSize: T.caption; font.features: { "tnum": 1 } }
                            Icon { name: page.eventIcon[modelData.type] || "alert-circle"; size: 14
                                color: modelData.level === "info" ? T.fog : T.levelColor(modelData.level) }
                            Label {
                                text: modelData.message
                                color: modelData.level === "info" ? T.moon : T.levelColor(modelData.level)
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                        }
                    }
                    Switch { text: "Mostrar a saída do processo"; checked: page.showOutput; onToggled: page.showOutput = checked; visible: server.output !== "" }
                    ScrollView {
                        visible: page.showOutput && server.output !== ""
                        Layout.fillWidth: true
                        Layout.preferredHeight: 256
                        TextArea {
                            readOnly: true
                            text: server.output
                            font.family: "monospace"; font.pixelSize: T.caption
                            wrapMode: TextEdit.NoWrap
                            background: Rectangle { color: T.night; radius: T.r4 }
                            onTextChanged: cursorPosition = length  // acompanha o fim, como um terminal
                        }
                    }
                }
            }
        }
    }
}
