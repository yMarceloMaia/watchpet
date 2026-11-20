#include "shell.h"

#include "servermanager.h"

#include <QAction>
#include <QFileInfo>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QIcon>
#include <QLocalSocket>
#include <QMenu>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSystemTrayIcon>

Shell::Shell(ServerManager *server, QObject *parent)
    : QObject(parent), m_server(server), m_settings("catwatch", "catwatch") {}

static QString instanceName() { return "catwatch-" + qEnvironmentVariable("USER", qEnvironmentVariable("USERNAME")); }

bool Shell::claimSingleInstance() {
    QLocalSocket probe;
    probe.connectToServer(instanceName());
    if (probe.waitForConnected(300)) {
        probe.write("show\n");
        probe.waitForBytesWritten(300);
        return false;
    }
    // Sobra de um Catwatch que fechou sem limpar o socket.
    QLocalServer::removeServer(instanceName());
    m_instance.listen(instanceName());
    connect(&m_instance, &QLocalServer::newConnection, this, [this] {
        while (auto *s = m_instance.nextPendingConnection()) {
            connect(s, &QLocalSocket::readyRead, this, [this, s] {
                if (s->readAll().startsWith("show"))
                    emit showWindowRequested();
                s->deleteLater();
            });
        }
    });
    return true;
}

bool Shell::trayAvailable() const { return QSystemTrayIcon::isSystemTrayAvailable(); }

void Shell::setupTray() {
    if (!trayAvailable())
        return;
    m_tray = new QSystemTrayIcon(QIcon(":/icon.svg"), this);
    m_menu = new QMenu();
    m_menu->addAction(tr("Abrir Catwatch"), this, &Shell::showWindowRequested);
    m_serverAction = m_menu->addAction(tr("Iniciar servidor"), this, [this] {
        const QString s = m_server->state();
        if (s == "running" || s == "external" || s == "starting")
            m_server->stop();
        else
            m_server->start();
    });
    m_menu->addSeparator();
    m_menu->addAction(tr("Sair"), this, &Shell::quit);
    m_tray->setContextMenu(m_menu);
    connect(m_tray, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason r) {
        if (r == QSystemTrayIcon::Trigger || r == QSystemTrayIcon::DoubleClick)
            emit showWindowRequested();
    });
    connect(m_server, &ServerManager::stateChanged, this, &Shell::updateTray);
    updateTray();
    m_tray->show();
}

void Shell::updateTray() {
    if (!m_tray)
        return;
    const QString s = m_server->state();
    const bool on = s == "running" || s == "external";
    m_serverAction->setText(on || s == "starting" ? tr("Parar servidor") : tr("Iniciar servidor"));
    m_serverAction->setEnabled(s != "stopping");
    const QString label = on ? tr("servidor rodando") : s == "starting" ? tr("servidor iniciando")
                        : s == "error" ? tr("erro no servidor") : tr("servidor parado");
    m_tray->setToolTip("Catwatch — " + label);
}

void Shell::setRunInBackground(bool on) {
    m_settings.setValue("shell/background", on);
    emit changed();
}

void Shell::setNotifyVisits(bool on) {
    m_settings.setValue("shell/notifyVisits", on);
    emit changed();
}

void Shell::setNotifyAlerts(bool on) {
    m_settings.setValue("shell/notifyAlerts", on);
    emit changed();
}

QString Shell::autostartPath() {
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/autostart/catwatch.desktop";
}

bool Shell::startWithSystem() const { return QFile::exists(autostartPath()); }

void Shell::setStartWithSystem(bool on) {
    // XDG autostart: o uwsm do Omarchy (e os desktops em geral) abre isso no login.
    if (on) {
        QDir().mkpath(QFileInfo(autostartPath()).path());
        QSaveFile f(autostartPath());
        if (f.open(QIODevice::WriteOnly)) {
            f.write("[Desktop Entry]\nType=Application\nName=Catwatch\n"
                    "Comment=Monitora os gatos em segundo plano\nIcon=catwatch\n"
                    "Exec=\"" + QCoreApplication::applicationFilePath().toUtf8() + "\" --background\n"
                    "X-GNOME-Autostart-enabled=true\n");
            f.commit();
        }
    } else {
        QFile::remove(autostartPath());
    }
    emit changed();
}

void Shell::notify(const QString &title, const QString &body, const QString &level) {
    if (m_tray) {
        const auto icon = level == "error" ? QSystemTrayIcon::Critical
                        : level == "warn"  ? QSystemTrayIcon::Warning
                                           : QSystemTrayIcon::Information;
        m_tray->showMessage(title, body, icon, 10000);
        return;
    }
    // Sem bandeja (ou sem StatusNotifier), o notify-send ainda chega ao daemon de notificações.
    QProcess::startDetached("notify-send", {"-a", "Catwatch", "-u", level == "error" ? "critical" : "normal", title, body});
}

void Shell::handleEvent(const QVariantMap &e) {
    const QString type = e.value("type").toString();
    if (type == "alert" && notifyAlerts())
        notify(tr("Catwatch — atenção"), e.value("message").toString(), e.value("level").toString());
    else if ((type == "camera_offline" || type == "camera_online") && notifyAlerts())
        notify(tr("Catwatch — câmera"), e.value("message").toString(), e.value("level").toString());
    else if (type == "visit" && notifyVisits())
        notify(tr("Catwatch — visita"), e.value("message").toString());
}

void Shell::quit() { emit quitRequested(); }
