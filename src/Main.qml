import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 900
    height: 640
    minimumWidth: 560
    minimumHeight: 420
    visible: true
    title: "Catwatch"
    color: "#0e0e10"

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    readonly property var kinds: ({ litter: "🚽 Caixa de areia", food: "🍽️ Comida", water: "💧 Água" })
    property bool helpVisible: false

    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; onActivated: Qt.quit() }
    Shortcut { sequence: "R"; context: Qt.ApplicationShortcut; onActivated: backend.refresh() }
    Shortcut { sequence: "1"; context: Qt.ApplicationShortcut; onActivated: tabs.currentIndex = 0 }
    Shortcut { sequence: "2"; context: Qt.ApplicationShortcut; onActivated: tabs.currentIndex = 1 }
    Shortcut { sequence: "3"; context: Qt.ApplicationShortcut; onActivated: tabs.currentIndex = 2 }

    // Tela de conexão
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

    ColumnLayout {
        anchors.fill: parent
        visible: backend.connected
        spacing: 0

        TabBar {
            id: tabs
            Layout.fillWidth: true
            TabButton { text: "Hoje (1)" }
            TabButton { text: "Câmeras (2)" }
            TabButton { text: "Histórico (3)" }
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

            // Hoje
            Flickable {
                contentHeight: todayFlow.height + 32
                clip: true
                ScrollBar.vertical: ScrollBar {}
                Flow {
                    id: todayFlow
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 12
                    Label { visible: backend.today.length === 0; text: "Nenhuma visita registrada hoje."; opacity: .6 }
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
                                Label { text: "🐱 " + modelData.cat; font.pixelSize: 18; font.bold: true }
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
            }

            // Câmeras
            Flickable {
                contentHeight: camFlow.height + 32
                clip: true
                ScrollBar.vertical: ScrollBar {}
                Flow {
                    id: camFlow
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 12
                    Repeater {
                        model: backend.cameras
                        Rectangle {
                            id: camCard
                            width: Math.max(300, (camFlow.width - 12) / Math.max(1, Math.min(2, backend.cameras.length)))
                            height: width * 9 / 16 + 34
                            color: "#1b1b1f"; radius: theme.radius
                            Image {
                                // Só busca imagem quando esta aba está visível, para não gastar rede e CPU à toa.
                                source: tabs.currentIndex === 1 ? backend.snapshotUrl(modelData.name, backend.frame) : ""
                                cache: false
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                height: parent.height - 34
                            }
                            Label {
                                anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                                text: (modelData.online ? "● " : "○ ") + modelData.name
                                color: modelData.online ? "#30d158" : "#ff453a"
                            }
                        }
                    }
                }
            }

            // Histórico
            ListView {
                clip: true
                model: backend.recent
                spacing: 1
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    width: ListView.view.width
                    text: win.kinds[modelData.kind] + "  ·  " + modelData.cat + "  ·  " + Math.round(modelData.end - modelData.start) + "s"
                    contentItem: RowLayout {
                        Label { text: parent.parent.text; Layout.fillWidth: true; elide: Text.ElideRight }
                        Label { text: new Date(modelData.start * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat); opacity: .6 }
                        ToolButton { text: "✕"; onClicked: backend.deleteVisit(modelData.id) }
                    }
                }
            }
        }
    }

    // Ajuda
    Rectangle {
        anchors.fill: parent
        visible: win.helpVisible
        color: "#000000cc"
        MouseArea { anchors.fill: parent; onClicked: win.helpVisible = false }
        Column {
            anchors.centerIn: parent
            spacing: 6
            Label { text: "Atalhos"; font.bold: true; font.pixelSize: 20 }
            Label { text: "1 / 2 / 3   Hoje · Câmeras · Histórico" }
            Label { text: "R   Atualizar" }
            Label { text: "?   Esta ajuda" }
            Label { text: "Q   Sair" }
        }
    }
}
