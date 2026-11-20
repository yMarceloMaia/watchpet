#pragma once

#include <QLocalServer>
#include <QObject>
#include <QSettings>

class QSystemTrayIcon;
class QMenu;
class QAction;
class ServerManager;

// Tudo que fica fora da janela: ícone na bandeja, notificações do sistema,
// iniciar com o sistema e garantir que só um Catwatch rode por vez.
class Shell : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool trayAvailable READ trayAvailable CONSTANT)
    Q_PROPERTY(bool runInBackground READ runInBackground WRITE setRunInBackground NOTIFY changed)
    Q_PROPERTY(bool startWithSystem READ startWithSystem WRITE setStartWithSystem NOTIFY changed)
    Q_PROPERTY(bool notifyVisits READ notifyVisits WRITE setNotifyVisits NOTIFY changed)
    Q_PROPERTY(bool notifyAlerts READ notifyAlerts WRITE setNotifyAlerts NOTIFY changed)
    // auto (segue o tema do sistema) | light | dark
    Q_PROPERTY(QString themeMode READ themeMode WRITE setThemeMode NOTIFY changed)

public:
    explicit Shell(ServerManager *server, QObject *parent = nullptr);

    // false quando outro Catwatch já está aberto (ele é trazido para frente e este deve sair).
    bool claimSingleInstance();
    void setupTray();

    bool trayAvailable() const;
    bool runInBackground() const { return m_settings.value("shell/background", true).toBool(); }
    void setRunInBackground(bool on);
    bool startWithSystem() const;
    void setStartWithSystem(bool on);
    bool notifyVisits() const { return m_settings.value("shell/notifyVisits", false).toBool(); }
    void setNotifyVisits(bool on);
    bool notifyAlerts() const { return m_settings.value("shell/notifyAlerts", true).toBool(); }
    void setNotifyAlerts(bool on);
    QString themeMode() const { return m_settings.value("shell/themeMode", "auto").toString(); }
    void setThemeMode(const QString &mode);

    Q_INVOKABLE void notify(const QString &title, const QString &body, const QString &level = "info");
    Q_INVOKABLE void quit();

    // Decide se um evento do servidor vira notificação do sistema.
    void handleEvent(const QVariantMap &event);

    static QString autostartPath();

signals:
    void changed();
    void showWindowRequested();
    void quitRequested();

private:
    void updateTray();

    ServerManager *m_server;
    QSettings m_settings;
    QLocalServer m_instance;
    QSystemTrayIcon *m_tray = nullptr;
    QMenu *m_menu = nullptr;
    QAction *m_serverAction = nullptr;
};
