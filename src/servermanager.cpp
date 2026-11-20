#include "servermanager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>

ServerManager::ServerManager(QObject *parent) : QObject(parent), m_settings("catwatch", "catwatch") {
    m_process.setProcessChannelMode(QProcess::MergedChannels);
    connect(&m_process, &QProcess::readyRead, this, [this] {
        appendOutput(QString::fromUtf8(m_process.readAll()));
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            m_wait.stop();
            setState("error", tr("Não consegui iniciar o Python: %1").arg(m_process.errorString()));
        }
    });
    connect(&m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) {
        m_wait.stop();
        if (m_state == "stopping") {
            setState("stopped");
            if (m_restartAfterStop) {
                m_restartAfterStop = false;
                start();
            }
            return;
        }
        const QString msg = tr("O servidor parou sozinho (código %1). Veja a saída do processo.").arg(code);
        setState("error", msg);
        emit crashed(msg);
    });

    m_wait.setInterval(1000);
    connect(&m_wait, &QTimer::timeout, this, [this] {
        ++m_waitedSeconds;
        probe([this](bool up) {
            if (m_state == "starting" && up) {
                m_wait.stop();
                setState("running");
                emit ready(localUrl(), localToken());
            } else if (m_state == "starting" && m_waitedSeconds > 180) {
                m_wait.stop();
                m_process.kill();
                setState("error", tr("O servidor não respondeu em 3 minutos."));
            } else if (m_state == "stopping" && !owned() && !up) {
                // Servidor externo que pedimos para encerrar.
                m_wait.stop();
                setState("stopped");
                if (m_restartAfterStop) {
                    m_restartAfterStop = false;
                    start();
                }
            } else if (m_state == "stopping" && !owned() && m_waitedSeconds > 20) {
                m_wait.stop();
                setState("error", tr("O servidor não encerrou. Feche-o pelo terminal onde ele roda."));
            }
        });
    });
}

ServerManager::~ServerManager() { shutdownOwned(); }

QString ServerManager::pythonPath(const QString &dir) {
#ifdef Q_OS_WIN
    return QDir(dir).filePath(".venv/Scripts/python.exe");
#else
    return QDir(dir).filePath(".venv/bin/python");
#endif
}

// Onde procurar o projeto do servidor quando o usuário ainda não escolheu.
QString ServerManager::defaultServerDir() {
    QStringList candidates;
    if (!qEnvironmentVariableIsEmpty("CATWATCH_SERVER_DIR"))
        candidates << qEnvironmentVariable("CATWATCH_SERVER_DIR");
    // Onde o install.sh coloca o servidor (~/.local/share/catwatch/server).
    candidates << QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/catwatch/server";
    const QString appDir = QCoreApplication::applicationDirPath();
    candidates << QDir(appDir).filePath("../../pet") << QDir(appDir).filePath("../pet")
               << QDir::home().filePath("projetos/meus/github/pet") << QDir::home().filePath("catwatch");
    for (const auto &c : candidates)
        if (QFileInfo::exists(QDir(c).filePath("catwatch/__main__.py")))
            return QDir(c).canonicalPath();
    return {};
}

void ServerManager::setServerDir(const QString &dir) {
    m_settings.setValue("server/dir", QDir::cleanPath(dir));
    emit settingsChanged();
}

void ServerManager::setServerDirUrl(const QString &url) { setServerDir(QUrl(url).toLocalFile()); }

bool ServerManager::serverDirValid() const {
    const QString dir = serverDir();
    return !dir.isEmpty() && QFileInfo::exists(QDir(dir).filePath("catwatch/__main__.py"))
           && QFileInfo::exists(pythonPath(dir));
}

void ServerManager::setAutoStart(bool on) {
    m_settings.setValue("server/autoStart", on);
    emit settingsChanged();
}

// Leitura mínima do config.yaml: só precisamos da porta e de onde fica o token.
QString ServerManager::readConfigValue(const QString &key) const {
    QFile f(QDir(serverDir()).filePath("config.yaml"));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QRegularExpression re("^\\s*" + QRegularExpression::escape(key) + ":\\s*['\"]?([^'\"\\s#]+)",
                                QRegularExpression::MultilineOption);
    const auto m = re.match(QString::fromUtf8(f.readAll()));
    return m.hasMatch() ? m.captured(1) : QString();
}

int ServerManager::port() const {
    bool ok = false;
    const int p = readConfigValue("port").toInt(&ok);
    return ok && p > 0 ? p : 8000;
}

QString ServerManager::localToken() const {
    QString db = readConfigValue("db");
    if (db.isEmpty())
        db = "data/catwatch.db";
    QFile f(QDir(serverDir()).filePath(QFileInfo(db).path() + "/token.txt"));
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
}

void ServerManager::setState(const QString &state, const QString &message) {
    m_state = state;
    m_message = message;
    emit stateChanged();
}

void ServerManager::probe(std::function<void(bool)> done) {
    QNetworkRequest req(QUrl(localUrl() + "/api/info"));
    req.setTransferTimeout(1500);
    auto *reply = m_net.get(req);
    connect(reply, &QNetworkReply::finished, this, [reply, done] {
        reply->deleteLater();
        const bool up = reply->error() == QNetworkReply::NoError
                        && QJsonDocument::fromJson(reply->readAll()).object().value("app").toString() == "catwatch";
        done(up);
    });
}

void ServerManager::appendOutput(const QString &text) {
    // Barras de progresso usam \r e códigos de cor ANSI; guardamos só o texto final de cada linha.
    static const QRegularExpression ansi("\x1b\\[[0-9;?]*[A-Za-z]");
    for (QString line : text.split('\n')) {
        line = line.section('\r', -1).remove(ansi).trimmed();
        if (!line.isEmpty())
            m_output << line;
    }
    while (m_output.size() > 400)
        m_output.removeFirst();
    emit outputChanged();
}

void ServerManager::detect(bool forceStart) {
    probe([this, forceStart](bool up) {
        if (up) {
            setState("external", tr("Servidor já estava rodando neste PC"));
            emit ready(localUrl(), localToken());
        } else if ((forceStart || autoStart()) && serverDirValid()) {
            start();
        }
    });
}

void ServerManager::start() {
    if (m_state == "starting" || m_state == "running" || m_state == "external" || owned())
        return;
    if (!serverDirValid()) {
        setState("error", tr("Escolha a pasta do servidor (precisa ter catwatch/ e .venv)."));
        return;
    }
    setState("starting", tr("Verificando…"));
    // Se algo já responde na porta, usa em vez de abrir outro (que falharia ao ocupar a porta).
    probe([this](bool up) {
        if (up) {
            setState("external", tr("Servidor já estava rodando neste PC"));
            emit ready(localUrl(), localToken());
            return;
        }
        const QString dir = serverDir();
        auto env = QProcessEnvironment::systemEnvironment();
        env.insert("PYTHONPATH", dir);
        env.insert("PYTHONUNBUFFERED", "1");
        m_process.setProcessEnvironment(env);
        m_process.setWorkingDirectory(dir);
        m_output.clear();
        appendOutput(tr("Iniciando servidor em %1…").arg(dir));
        m_process.start(pythonPath(dir), {"-m", "catwatch", "--data-dir", dir});
        setState("starting", tr("Carregando os modelos de IA (pode levar até 1 minuto)…"));
        m_waitedSeconds = 0;
        m_wait.start();
    });
}

void ServerManager::stop() {
    if (owned()) {
        setState("stopping", tr("Encerrando…"));
        m_process.terminate();  // SIGTERM: o uvicorn fecha as conexões e o banco direito
        QTimer::singleShot(8000, this, [this] {
            if (owned())
                m_process.kill();
        });
        return;
    }
    if (m_state != "external" && m_state != "running")
        return;
    // Servidor que não fomos nós que abrimos: pede para ele se encerrar (só aceito do próprio PC).
    QNetworkRequest req(QUrl(localUrl() + "/api/shutdown"));
    req.setRawHeader("X-Token", localToken().toUtf8());
    auto *reply = m_net.post(req, QByteArray());
    connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
    setState("stopping", tr("Encerrando…"));
    m_waitedSeconds = 0;
    m_wait.start();
}

void ServerManager::restart() {
    if (m_state == "stopped" || m_state == "error") {
        start();
        return;
    }
    m_restartAfterStop = true;
    stop();
}

void ServerManager::shutdownOwned() {
    if (!owned())
        return;
    m_state = "stopping";
    m_process.terminate();
    if (!m_process.waitForFinished(8000))
        m_process.kill();
}
