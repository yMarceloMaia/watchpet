// catwatch — painel para acompanhar os gatos e controlar o servidor Catwatch deste PC.

#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#include "backend.h"
#include "servermanager.h"
#include "shell.h"
#include "theme.h"

int main(int argc, char *argv[]) {
    // QApplication (e não QGuiApplication) porque o ícone na bandeja e o menu dele são widgets.
    QApplication app(argc, argv);
    app.setApplicationName("catwatch");
    app.setApplicationVersion("1.2.1");
    app.setDesktopFileName("catwatch");
    app.setWindowIcon(QIcon::fromTheme("catwatch", QIcon(":/icon.svg")));
    // Fechar a janela não encerra o app quando ele fica na bandeja; o QML decide.
    app.setQuitOnLastWindowClosed(false);
    // Variante densa do Material: campos e listas mais baixos, num ritmo de 8 em 8.
    qputenv("QT_QUICK_CONTROLS_MATERIAL_VARIANT", "Dense");
    QQuickStyle::setStyle("Material");

    // --background: aberto pelo login (iniciar com o sistema); começa só na bandeja.
    const bool background = app.arguments().contains("--background");

    ServerManager server;
    Shell shell(&server);
    if (!shell.claimSingleInstance())
        return 0;  // o Catwatch que já estava aberto vem para a frente
    shell.setupTray();

    Theme theme;
    Backend backend;

    // Servidor local pronto: conecta nele, a não ser que o usuário esteja olhando outro servidor.
    QObject::connect(&server, &ServerManager::ready, &backend, [&](const QString &url, const QString &token) {
        if (!backend.connected() || backend.isLocal())
            backend.connectTo(url, token);
    });
    QObject::connect(&server, &ServerManager::crashed, &shell, [&](const QString &msg) {
        shell.notify(QObject::tr("Catwatch — servidor parou"), msg, "error");
    });
    QObject::connect(&backend, &Backend::newEvent, &shell, &Shell::handleEvent);
    QObject::connect(&shell, &Shell::quitRequested, &app, &QApplication::quit);
    QObject::connect(&app, &QApplication::aboutToQuit, &server, &ServerManager::shutdownOwned);

    QQmlApplicationEngine engine;
    auto *ctx = engine.rootContext();
    ctx->setContextProperty("theme", &theme);
    ctx->setContextProperty("backend", &backend);
    ctx->setContextProperty("server", &server);
    ctx->setContextProperty("shell", &shell);
    ctx->setContextProperty("startHidden", background && shell.trayAvailable());
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    // Aberto pelo login: a ideia é monitorar, então liga o servidor mesmo sem o autoStart.
    server.detect(background);
    return app.exec();
}
