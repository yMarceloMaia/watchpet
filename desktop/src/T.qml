pragma Singleton
import QtQuick

// Tokens visuais do Catwatch ("vigília noturna"). Os mesmos valores estão em
// catwatch-mobile/src/ui.tsx; mude nos dois lugares.
QtObject {
    // Claro ou escuro: o Main.qml liga isto à preferência do usuário e ao tema do sistema.
    property bool dark: true

    // Superfícies. Escuro: índigo noturno. Claro: manhã, um cinza-azulado frio.
    readonly property color night: dark ? "#171A2B" : "#F3F4F9"   // fundo do conteúdo
    readonly property color dusk: dark ? "#1F2338" : "#FFFFFF"    // painéis e trilho
    readonly property color haze: dark ? "#2A2F4A" : "#E7E9F2"    // campos, hover, faixa do dia
    readonly property color seam: dark ? "#363C5E" : "#D5D8E6"    // linhas de 1 px
    readonly property color moon: dark ? "#ECEAF4" : "#1E2236"    // texto
    readonly property color fog: dark ? "#9EA1BD" : "#626783"     // texto secundário

    // As três necessidades do dia: a mesma cor em todo lugar onde aparecem.
    // No claro, tons mais fundos para ler bem sobre o branco.
    readonly property color sand: dark ? "#D8BE8A" : "#A27A2C"    // caixa de areia
    readonly property color paw: dark ? "#F2899B" : "#CC4A66"     // comida
    readonly property color pool: dark ? "#66C6F2" : "#1B86BE"    // água

    readonly property color alert: dark ? "#FF6B6B" : "#D23C3C"
    readonly property color warn: dark ? "#F4C152" : "#A9780A"
    readonly property color ok: dark ? "#6EDC9A" : "#25915A"
    // Véu atrás de diálogos e fotos ampliadas.
    readonly property color scrim: dark ? "#cc0b0d18" : "#991e2236"

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
        "download": 0xf01da, "upload": 0xf0552, "vector-polygon": 0xf0560, "swap-horizontal": 0xf04e1, "folder-open": 0xf0770,
        "content-save": 0xf0193, "power": 0xf0425, "eye": 0xf0208, "eye-off": 0xf0209,
        "clock-outline": 0xf0150, "web": 0xf059f, "lan-disconnect": 0xf0319,
        "brightness-auto": 0xf00e1, "white-balance-sunny": 0xf05a8, "weather-night": 0xf0594
    })
}
