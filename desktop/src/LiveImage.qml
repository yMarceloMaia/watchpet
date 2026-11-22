import QtQuick
import "."

// Imagem ao vivo de uma câmera, quadro a quadro.
//
// O próximo quadro só é pedido depois que o anterior chegou: com um relógio fixo, quando o
// servidor demorava mais que o intervalo (processador ocupado analisando gatos, imagem noturna
// mais pesada), cada pedido cancelava o anterior e a imagem nunca aparecia. E o quadro novo
// carrega na imagem escondida: a que está à mostra só é trocada quando ele está pronto, sem
// piscar em branco.
Item {
    id: root
    property string camera: ""
    property bool running: false
    // Pausa entre um quadro e o pedido do próximo.
    property int interval: 400

    property int _front: 0
    property int _seq: 0

    function _next() {
        if (!running || camera === "")
            return
        const back = _front === 0 ? b : a
        back.source = backend.snapshotUrl(camera, ++_seq)
        watchdog.restart()
    }
    function _loaded(img) {
        if (img.source == "" || (img === a) === (_front === 0))
            return  // a imagem à mostra também muda de estado quando é limpa; só a de trás conta
        if (img.status === Image.Ready) {
            _front = img === a ? 0 : 1
            watchdog.stop()
            pace.interval = root.interval
            pace.restart()
        } else if (img.status === Image.Error) {
            watchdog.stop()
            pace.interval = 2000  // servidor fora ou câmera sem imagem: tenta de novo com calma
            pace.restart()
        }
    }

    onRunningChanged: {
        if (running)
            return _next()
        pace.stop()
        watchdog.stop()
        a.source = ""  // fora da tela ou câmera fora do ar: não guarda quadro velho
        b.source = ""
    }
    onCameraChanged: { a.source = ""; b.source = ""; _next() }
    Component.onCompleted: _next()

    Timer { id: pace; onTriggered: root._next() }
    // Pedido que nunca responde (rede caiu no meio): desiste dele e pede outro.
    Timer { id: watchdog; interval: 10000; onTriggered: root._next() }

    Image {
        id: a
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        asynchronous: true; cache: false
        visible: root.running && root._front === 0 && status === Image.Ready
        onStatusChanged: root._loaded(a)
    }
    Image {
        id: b
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        asynchronous: true; cache: false
        visible: root.running && root._front === 1 && status === Image.Ready
        onStatusChanged: root._loaded(b)
    }
}
