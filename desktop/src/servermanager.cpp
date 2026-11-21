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

#include <QEventLoop>

#ifdef Q_OS_LINUX
#include <csignal>
#include <sys/prctl.h>
#endif
#ifdef Q_OS_WIN
#include <windows.h>
#endif

ServerManager::ServerManager(QObject *parent) : QObject(parent), m_settings("catwatch", "catwatch") {
    m_process.setProcessChannelMode(QProcess::MergedChannels);
#ifdef Q_OS_WIN
    // Equivalente ao PR_SET_PDEATHSIG do Linux: com o app fechado (até à força), o Windows
    // encerra os processos do job, e o servidor não fica órfão ocupando a porta.
    if (HANDLE job = CreateJobObjectW(nullptr, nullptr)) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION info{};
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info, sizeof info);
        m_job = job;
    }
    connect(&m_process, &QProcess::started, this, [this] {
        if (!m_job)
            return;
        if (HANDLE proc = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, FALSE, DWORD(m_process.processId()))) {
            AssignProcessToJobObject(static_cast<HANDLE>(m_job), proc);
            CloseHandle(proc);
        }
    });
    // Servidor sem janela de console: o app mostra a saída dele na aba Servidor.
    m_process.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *args) {
        args->flags |= CREATE_NO_WINDOW;
    });
#endif
    connect(&m_process, &QProcess::readyRead, this, [this] {
        appendOutput(QString::fromUtf8(m_process.readAll()));
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            m_wait.stop();
            setState("error", tr("Não consegui iniciar o servidor: %1").arg(m_process.errorString()));
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
        // 10 = pasta de dados em uso, 11 = porta em uso: outro servidor ganhou a corrida.
        // Se há um Catwatch respondendo na porta, é só usar ele; não é erro.
        const QString why = lastServerMessage();
        probe([this, code, why](Probe p) {
            if (p == Ours) {
                useExisting(tr("Outro servidor Catwatch já estava rodando; usando ele."));
                return;
            }
            if (p == Foreign) {
                setState("error", foreignMessage());
                emit crashed(foreignMessage());
                return;
            }
            if (const qint64 pid = otherServerPid(); code == 10 && pid) {
                waitForOther(pid);
                return;
            }
            const QString msg = why.isEmpty() ? tr("O servidor parou sozinho (código %1). Veja a saída do processo.").arg(code)
                                              : tr("O servidor parou: %1").arg(why);
            setState("error", msg);
            emit crashed(msg);
        });
    });

    m_wait.setInterval(1000);
    connect(&m_wait, &QTimer::timeout, this, [this] {
        ++m_waitedSeconds;
        probe([this](Probe p) {
            const bool up = p != Down;
            if (m_otherPid) {
                // Servidor de fora do app carregando: assim que responder, usamos ele.
                if (p == Ours) {
                    m_otherPid = 0;
                    m_wait.stop();
                    useExisting(tr("Servidor aberto fora do app"));
                } else if (p == Foreign) {
                    m_otherPid = 0;
                    m_wait.stop();
                    setState("error", foreignMessage());
                } else if (otherServerPid() != m_otherPid) {
                    m_otherPid = 0;  // ele desistiu ou morreu: seguimos o fluxo normal
                    m_wait.stop();
                    setState("stopped");
                    if (autoStart() && serverDirValid())
                        start();
                } else if (m_waitedSeconds > 180) {
                    m_otherPid = 0;
                    m_wait.stop();
                    setState("error", tr("O servidor aberto fora do app não respondeu em 3 minutos."));
                }
                return;
            }
            // Enquanto o nosso carrega, um servidor de outra pasta pode responder na porta: não é o nosso.
            // O nosso vai falhar ao ocupar a porta, e o aviso sai quando ele encerrar.
            if (m_state == "starting" && p == Ours) {
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

ServerManager::~ServerManager() {
    shutdownOwned();
#ifdef Q_OS_WIN
    if (m_job)
        CloseHandle(static_cast<HANDLE>(m_job));
#endif
}

QString ServerManager::bundledExe(const QString &dir) {
#ifdef Q_OS_WIN
    const QString exe = QDir(dir).filePath("catwatch-server.exe");
#else
    const QString exe = QDir(dir).filePath("catwatch-server");
#endif
    return !dir.isEmpty() && QFileInfo(exe).isFile() ? exe : QString();
}

QString ServerManager::platformDataDir() {
    // Os mesmos caminhos que o executável usa quando não recebe --data-dir.
#ifdef Q_OS_WIN
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/Catwatch";
#else
    return QDir::home().filePath(".local/share/catwatch/server");
#endif
}

QString ServerManager::dataDir() const { return bundled() ? platformDataDir() : serverDir(); }

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
    // Instalador: o servidor executável vai numa pasta "server" ao lado do app.
    const QString bundledDir = QDir(QCoreApplication::applicationDirPath()).filePath("server");
    if (!bundledExe(bundledDir).isEmpty())
        return QDir(bundledDir).canonicalPath();
    // Onde o install.sh coloca o servidor (~/.local/share/catwatch/server).
    candidates << QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/catwatch/server";
    const QString appDir = QCoreApplication::applicationDirPath();
    // No repositório (watchpet/desktop/build/catwatch): o servidor fica em watchpet/server.
    candidates << QDir(appDir).filePath("../../server") << QDir(appDir).filePath("../server");
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
    if (!bundledExe(dir).isEmpty())
        return true;
    return !dir.isEmpty() && QFileInfo::exists(QDir(dir).filePath("catwatch/__main__.py"))
           && QFileInfo::exists(pythonPath(dir));
}

void ServerManager::setAutoStart(bool on) {
    m_settings.setValue("server/autoStart", on);
    emit settingsChanged();
}

// Leitura mínima do config.yaml: só precisamos da porta e de onde fica o token.
QString ServerManager::readConfigValue(const QString &key) const {
    QFile f(QDir(dataDir()).filePath("config.yaml"));
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
    QFile f(QDir(dataDir()).filePath(QFileInfo(db).path() + "/token.txt"));
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
}

void ServerManager::setState(const QString &state, const QString &message) {
    m_state = state;
    m_message = message;
    emit stateChanged();
}

void ServerManager::probe(std::function<void(Probe)> done) {
    QNetworkRequest req(QUrl(localUrl() + "/api/check"));
    req.setRawHeader("X-Token", localToken().toUtf8());
    req.setTransferTimeout(1500);
    auto *reply = m_net.get(req);
    connect(reply, &QNetworkReply::finished, this, [reply, done] {
        reply->deleteLater();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        done(status == 200 ? Ours : status == 401 ? Foreign : Down);
    });
}

QString ServerManager::foreignMessage() const {
    return tr("A porta %1 está ocupada por um servidor Catwatch de outra pasta (outro token). "
              "Feche esse servidor ou mude a porta nas configurações.").arg(port());
}

void ServerManager::useExisting(const QString &message) {
    setState("external", message);
    emit ready(localUrl(), localToken());
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
    probe([this, forceStart](Probe p) {
        if (p == Ours) {
            useExisting(tr("Servidor já estava rodando neste PC"));
        } else if (p == Foreign) {
            setState("error", foreignMessage());
        } else if (const qint64 pid = otherServerPid()) {
            waitForOther(pid);  // aberto pelo terminal agora há pouco: ainda carregando os modelos
        } else if ((forceStart || autoStart()) && serverDirValid()) {
            start();
        }
    });
}

qint64 ServerManager::otherServerPid() const {
    QFile f(QDir(dataDir()).filePath(".catwatch.lock"));
    if (!f.open(QIODevice::ReadOnly))
        return 0;
    const qint64 pid = QString::fromUtf8(f.readAll()).trimmed().toLongLong();
    if (pid <= 0 || pid == m_process.processId())
        return 0;
#ifdef Q_OS_LINUX
    // A trava fica no arquivo mesmo depois do servidor morrer; o PID só vale se o processo
    // ainda existe e é mesmo um Catwatch (PIDs são reaproveitados).
    QFile cmd(QString("/proc/%1/cmdline").arg(pid));
    if (!cmd.open(QIODevice::ReadOnly) || !cmd.readAll().contains("catwatch"))
        return 0;
    return pid;
#else
    return 0;  // no Windows, o app só confia na porta
#endif
}

void ServerManager::waitForOther(qint64 pid) {
    m_otherPid = pid;
    m_waitedSeconds = 0;
    setState("starting", tr("Outro servidor Catwatch está iniciando (PID %1). Aguardando ele em vez de abrir outro.").arg(pid));
    m_wait.start();
}

QString ServerManager::lastServerMessage() const {
    for (auto it = m_output.crbegin(); it != m_output.crend(); ++it)
        if (it->startsWith("catwatch: "))
            return it->mid(10);
    return {};
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
    probe([this](Probe p) {
        if (p == Ours) {
            useExisting(tr("Servidor já estava rodando neste PC"));
            return;
        }
        if (p == Foreign) {
            setState("error", foreignMessage());
            return;
        }
        if (const qint64 pid = otherServerPid()) {
            waitForOther(pid);
            return;
        }
        const QString dir = serverDir();
        const QString exe = bundledExe(dir);
        const QString data = dataDir();
        QDir().mkpath(data);
        auto env = QProcessEnvironment::systemEnvironment();
        env.insert("PYTHONPATH", dir);
        env.insert("PYTHONUNBUFFERED", "1");
        m_process.setProcessEnvironment(env);
#ifdef Q_OS_LINUX
        // Se o app morrer de qualquer jeito (até kill -9), o kernel manda SIGTERM ao servidor,
        // que fecha o banco direito, em vez de deixá-lo órfão ocupando a porta e a placa de vídeo.
        m_process.setChildProcessModifier([] { ::prctl(PR_SET_PDEATHSIG, SIGTERM); });
#endif
        m_process.setWorkingDirectory(data);
        m_output.clear();
        appendOutput(tr("Iniciando servidor (dados em %1)…").arg(QDir::toNativeSeparators(data)));
        if (!exe.isEmpty())
            m_process.start(exe, {"--data-dir", data});
        else
            m_process.start(pythonPath(dir), {"-m", "catwatch", "--data-dir", dir});
        setState("starting", tr("Carregando os modelos de IA (pode levar até 1 minuto)…"));
        m_waitedSeconds = 0;
        m_wait.start();
    });
}

void ServerManager::stop() {
    if (m_otherPid) {
        // Esperávamos um servidor aberto fora do app: paramos de esperar, mas ele é de quem o abriu.
        m_otherPid = 0;
        m_wait.stop();
        setState("stopped", tr("O servidor aberto fora do app continua iniciando; feche-o por onde ele foi aberto."));
        return;
    }
    if (owned()) {
        setState("stopping", tr("Encerrando…"));
#ifdef Q_OS_WIN
        requestShutdown();
#else
        m_process.terminate();  // SIGTERM: o uvicorn fecha as conexões e o banco direito
#endif
        QTimer::singleShot(10000, this, [this] {
            if (owned())
                m_process.kill();
        });
        return;
    }
    if (m_state != "external" && m_state != "running")
        return;
    // Servidor que não fomos nós que abrimos: pede para ele se encerrar (só aceito do próprio PC).
    requestShutdown();
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

void ServerManager::requestShutdown() {
    QNetworkRequest req(QUrl(localUrl() + "/api/shutdown"));
    req.setRawHeader("X-Token", localToken().toUtf8());
    req.setTransferTimeout(3000);
    auto *reply = m_net.post(req, QByteArray());
    connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
}

void ServerManager::shutdownOwned() {
    if (!owned())
        return;
    m_state = "stopping";
#ifdef Q_OS_WIN
    // O app está saindo: espera a resposta do pedido de encerramento antes de seguir.
    QNetworkRequest req(QUrl(localUrl() + "/api/shutdown"));
    req.setRawHeader("X-Token", localToken().toUtf8());
    req.setTransferTimeout(3000);
    QEventLoop loop;
    auto *reply = m_net.post(req, QByteArray());
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    reply->deleteLater();
#else
    m_process.terminate();
#endif
    if (!m_process.waitForFinished(10000))
        m_process.kill();
}
