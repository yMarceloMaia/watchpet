pragma Singleton
import QtQuick

// Tokens visuais do Catwatch ("vigília noturna"). Os mesmos valores estão em
// catwatch-mobile/src/ui.tsx; mude nos dois lugares.
QtObject {
    // Superfícies: índigo noturno, do fundo para a frente.
    readonly property color night: "#171A2B"   // fundo do conteúdo
    readonly property color dusk: "#1F2338"    // painéis e trilho
    readonly property color haze: "#2A2F4A"    // campos, hover, faixa do dia
    readonly property color seam: "#363C5E"    // linhas de 1 px
    readonly property color moon: "#ECEAF4"    // texto
    readonly property color fog: "#9EA1BD"     // texto secundário

    // As três necessidades do dia: a mesma cor em todo lugar onde aparecem.
    readonly property color sand: "#D8BE8A"    // caixa de areia
    readonly property color paw: "#F2899B"     // comida
    readonly property color pool: "#66C6F2"    // água

    readonly property color alert: "#FF6B6B"
    readonly property color warn: "#F4C152"
    readonly property color ok: "#6EDC9A"

    // Escala binária: espaços e cantos só nestes valores.
    readonly property int s2: 2
    readonly property int s4: 4
    readonly property int s8: 8
    readonly property int s16: 16
    readonly property int s32: 32
    readonly property int s64: 64
    readonly property int r2: 2    // traços, chips
    readonly property int r4: 4    // controles, imagens
    readonly property int r8: 8    // painéis

    // O app é em português: datas e números em pt-BR, independente do idioma do sistema.
    readonly property var locale: Qt.locale("pt_BR")

    // Tipo
    readonly property int caption: 12
    readonly property int body: 14
    readonly property int strong: 16
    readonly property int title: 20
    readonly property int display: 24

    readonly property FontLoader regular: FontLoader { source: "qrc:/fonts/Recursive_400Regular.ttf" }
    readonly property FontLoader medium: FontLoader { source: "qrc:/fonts/Recursive_500Medium.ttf" }
    readonly property FontLoader semibold: FontLoader { source: "qrc:/fonts/Recursive_600SemiBold.ttf" }
    readonly property FontLoader bold: FontLoader { source: "qrc:/fonts/Recursive_700Bold.ttf" }
    readonly property FontLoader icons: FontLoader { source: "qrc:/fonts/MaterialCommunityIcons.ttf" }
    readonly property string family: regular.font.family
    readonly property string iconFamily: icons.font.family

    readonly property var kindName: ({ litter: "Caixa de areia", food: "Comida", water: "Água" })
    readonly property var kindShort: ({ litter: "Caixa", food: "Comida", water: "Água" })
    readonly property var kindIcon: ({ litter: "grain", food: "bowl-mix", water: "water" })
    function kindColor(kind) { return kind === "litter" ? sand : kind === "food" ? paw : kind === "water" ? pool : fog }
    function levelColor(level) { return level === "error" ? alert : level === "warn" ? warn : fog }

    // Material Design Icons: só os que o app usa.
    readonly property var glyph: ({
        "paw": 0xf03e9, "cctv": 0xf07ae, "cat": 0xf011b, "history": 0xf02da, "server": 0xf048b,
        "cellphone": 0xf011c, "grain": 0xf0d7c, "bowl-mix": 0xf0617, "water": 0xf058c,
        "alert": 0xf0026, "alert-circle": 0xf0028, "check-circle": 0xf05e0, "close": 0xf0156,
        "plus": 0xf0415, "camera": 0xf0100, "image-multiple": 0xf02f9, "delete-outline": 0xf09e7,
        "refresh": 0xf0450, "play": 0xf040a, "stop": 0xf04db, "restart": 0xf0709, "qrcode-scan": 0xf0433,
        "download": 0xf01da, "vector-polygon": 0xf0560, "swap-horizontal": 0xf04e1, "folder-open": 0xf0770,
        "content-save": 0xf0193, "power": 0xf0425, "eye": 0xf0208, "eye-off": 0xf0209,
        "clock-outline": 0xf0150, "web": 0xf059f, "lan-disconnect": 0xf0319
    })
}
