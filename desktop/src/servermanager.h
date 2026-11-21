#pragma once

#include <QNetworkAccessManager>
#include <functional>
#include <QObject>
#include <QProcess>
#include <QSettings>
#include <QStringList>
#include <QTimer>

// Liga, desliga e acompanha o servidor neste PC. Ele pode ser o projeto Python (pasta com
// catwatch/ e .venv) ou o executável que vem junto com o app no instalador (server/catwatch-server).
// Se já houver um servidor rodando na porta (iniciado pelo terminal ou pelo systemd),
// ele é reconhecido como "externo" e usado do mesmo jeito.
class ServerManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString message READ message NOTIFY stateChanged)
    Q_PROPERTY(bool owned READ owned NOTIFY stateChanged)
    Q_PROPERTY(int port READ port NOTIFY settingsChanged)
    Q_PROPERTY(QString serverDir READ serverDir WRITE setServerDir NOTIFY settingsChanged)
    Q_PROPERTY(bool serverDirValid READ serverDirValid NOTIFY settingsChanged)
    Q_PROPERTY(bool autoStart READ autoStart WRITE setAutoStart NOTIFY settingsChanged)
    Q_PROPERTY(QString output READ output NOTIFY outputChanged)
    // Servidor executável embutido no app (instalador); os dados ficam em dataDir.
    Q_PROPERTY(bool bundled READ bundled NOTIFY settingsChanged)
    Q_PROPERTY(QString dataDir READ dataDir NOTIFY settingsChanged)

public:
    explicit ServerManager(QObject *parent = nullptr);
    ~ServerManager() override;

    // stopped | starting | running | external | stopping | error
    QString state() const { return m_state; }
    QString message() const { return m_message; }
    bool owned() const { return m_process.state() != QProcess::NotRunning; }
    int port() const;
    QString serverDir() const { return m_settings.value("server/dir", defaultServerDir()).toString(); }
    void setServerDir(const QString &dir);
    bool serverDirValid() const;
    bool autoStart() const { return m_settings.value("server/autoStart", true).toBool(); }
    void setAutoStart(bool on);
    QString output() const { return m_output.join('\n'); }
    bool bundled() const { return !bundledExe(serverDir()).isEmpty(); }
    QString dataDir() const;

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void setServerDirUrl(const QString &url);  // vem do FolderDialog
    Q_INVOKABLE QString localToken() const;
    Q_INVOKABLE QString localUrl() const { return QString("http://127.0.0.1:%1").arg(port()); }

    // Na abertura do app: usa um servidor que já esteja rodando, ou liga o nosso se autoStart.
    void detect(bool forceStart = false);
    // Ao sair do app: para o servidor que nós iniciamos (espera ele fechar o banco direito).
    void shutdownOwned();

    static QString defaultServerDir();
    static QString pythonPath(const QString &dir);
    // O executável do servidor nessa pasta, se ela tiver um (instalação pelo instalador).
    static QString bundledExe(const QString &dir);
    // Onde o executável guarda os dados por padrão (%LOCALAPPDATA%\Catwatch no Windows).
    static QString platformDataDir();

signals:
    void stateChanged();
    void settingsChanged();
    void outputChanged();
    void ready(const QString &url, const QString &token);
    void crashed(const QString &message);

private:
    void setState(const QString &state, const QString &message = {});
    // Quem responde na porta: ninguém, o servidor desta pasta (aceita o nosso token) ou
    // um servidor Catwatch de outra pasta (recusa o token): nesse caso não dá para usá-lo.
    enum Probe { Down, Ours, Foreign };
    void probe(std::function<void(Probe)> done);
    QString foreignMessage() const;
    void useExisting(const QString &message);
    void appendOutput(const QString &text);
    // PID do servidor que segura a trava da pasta de dados (.catwatch.lock), se ele ainda vive.
    qint64 otherServerPid() const;
    void waitForOther(qint64 pid);
    QString lastServerMessage() const;
    QString readConfigValue(const QString &key) const;
    // Pede ao servidor para encerrar (só aceito do próprio PC). No Windows é o jeito limpo de
    // parar o nosso processo: o "terminate" do Qt não alcança programas de console.
    void requestShutdown();

    QSettings m_settings;
    QProcess m_process;
    QNetworkAccessManager m_net;
    QTimer m_wait;
    int m_waitedSeconds = 0;
    bool m_restartAfterStop = false;
    // Esperando um servidor aberto fora do app (terminal, systemd) terminar de carregar.
    qint64 m_otherPid = 0;
    QString m_state = "stopped", m_message;
    QStringList m_output;
#ifdef Q_OS_WIN
    void *m_job = nullptr;  // Job Object: o Windows encerra o servidor se o app morrer
#endif
};
