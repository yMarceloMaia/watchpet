import QtQuick
import QtQuick.Controls
import "."

// Um dia de um gato em 24 horas: cada visita é um traço na cor do tipo, na hora em que aconteceu.
// O trecho do dia que ainda não chegou fica apagado; a linha clara marca agora.
Item {
    id: strip
    property var visits: []
    property real dayStart: 0
    property real now: Date.now() / 1000
    readonly property real span: 86400
    function xAt(t) { return Math.max(0, Math.min(1, (t - dayStart) / span)) * track.width }

    implicitHeight: track.height + T.s4 + T.s16

    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: T.s32
        radius: T.r4
        color: T.haze
        clip: true

        // O futuro: mais escuro que o que já passou.
        Rectangle {
            x: strip.xAt(strip.now); width: parent.width - x; height: parent.height
            color: T.night; opacity: .55
        }
        Repeater {
            model: [6, 12, 18]
            Rectangle { x: track.width * modelData / 24; width: 1; height: track.height; color: T.seam }
        }
        Repeater {
            model: strip.visits
            Rectangle {
                id: tick
                x: Math.min(track.width - width, Math.max(0, strip.xAt(modelData.start) - width / 2))
                y: T.s4; width: T.s4; height: track.height - T.s8
                radius: T.r2
                color: T.kindColor(modelData.kind)
                HoverHandler { id: hover }
                ToolTip.visible: hover.hovered
                ToolTip.delay: 150
                ToolTip.text: T.kindName[modelData.kind] + " às "
                              + new Date(modelData.start * 1000).toLocaleTimeString(T.locale, "HH:mm")
                              + ", ficou " + Math.round(modelData.presence ?? (modelData.end - modelData.start)) + " s"
            }
        }
        Rectangle {
            visible: strip.now >= strip.dayStart && strip.now < strip.dayStart + strip.span
            x: strip.xAt(strip.now) - 1; width: T.s2; height: track.height
            color: T.moon; opacity: .8
        }
    }
    Repeater {
        model: [0, 6, 12, 18, 24]
        Label {
            y: track.height + T.s4
            x: modelData === 0 ? 0 : modelData === 24 ? strip.width - width : strip.width * modelData / 24 - width / 2
            text: modelData + "h"
            font.pixelSize: T.caption
            font.features: { "tnum": 1 }
            color: T.fog
        }
    }
}
