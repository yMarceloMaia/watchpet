#include "backend.h"

#include <QDateTime>
#include <QFile>
#include <QSaveFile>
#include <memory>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>

Backend::Backend(QObject *parent) : QObject(parent), m_settings("catwatch", "catwatch") {
    m_poll.setInterval(5000);
    connect(&m_poll, &QTimer::timeout, this, &Backend::refresh);
    m_eventsPoll.setInterval(3000);
    connect(&m_eventsPoll, &QTimer::timeout, this, &Backend::pollEvents);

    const QString url = savedUrl(), token = savedToken();
    if (!url.isEmpty() && !token.isEmpty())
        connectTo(url, token);
}

QNetworkRequest Backend::request(const QString &path) const {
    QNetworkRequest req(QUrl(m_url + path));
    req.setRawHeader("X-Token", m_token.toUtf8());
    req.setTransferTimeout(15000);
    return req;
}

QNetworkReply *Backend::get(const QString &path) { return m_net.get(request(path)); }

// Mostra o motivo que o servidor deu ("detail"), senão o erro de rede.
void Backend::finishAction(QNetworkReply *reply, const QString &okText, const QByteArray &readBody) {
    reply->deleteLater();
    if (reply->error() == QNetworkReply::NoError) {
        if (!okText.isEmpty())
            emit message(okText, false);
    } else {
        const QByteArray body = readBody.isNull() ? reply->readAll() : readBody;
        const QString detail = QJsonDocument::fromJson(body).object().value("detail").toString();
        emit message(detail.isEmpty() ? reply->errorString() : detail, true);
    }
    refresh();
}

void Backend::send(const QString &method, const QString &path, const QByteArray &body, const QString &okText) {
    auto req = request(path);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    auto *reply = m_net.sendCustomRequest(req, method.toUtf8(), body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, okText] { finishAction(reply, okText); });
}

void Backend::setError(const QString &e) {
    if (e == m_error)
        return;
    m_error = e;
    emit errorChanged();
}

void Backend::connectTo(const QString &url, const QString &token) {
    QString u = url.trimmed();
    while (u.endsWith('/'))
        u.chop(1);
    if (!u.startsWith("http://") && !u.startsWith("https://"))
        u = "http://" + u;
    m_url = u;
    m_token = token.trimmed();
    setError({});

    auto *reply = get("/api/check");
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() == QNetworkReply::NoError) {
            m_settings.setValue("url", m_url);
            m_settings.setValue("token", m_token);
            m_connected = true;
            m_lastEventId = 0;
            m_eventsLoaded = false;
            m_events.clear();
            emit eventsChanged();
            emit connectedChanged();
            m_poll.start();
            m_eventsPoll.start();
            refresh();
            pollEvents();
            loadSettings();
            loadPair();
        } else {
            m_connected = false;
            emit connectedChanged();
            const int code = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            setError(code == 401 ? tr("Token inválido") : tr("Não consegui conectar: %1").arg(reply->errorString()));
        }
    });
}

void Backend::disconnectServer() {
    m_poll.stop();
    m_eventsPoll.stop();
    m_settings.remove("token");
    m_connected = false;
    emit connectedChanged();
}

QVariantList Backend::pivot(const QVariantList &counts, const QStringList &keys) {
    QMap<QString, QVariantMap> rows;  // chave ordenada: dia|gato
    for (const auto &v : counts) {
        const auto o = v.toMap();
        QStringList id;
        for (const auto &k : keys)
            id << o[k].toString();
        auto &row = rows[id.join('|')];
        for (const auto &k : keys)
            row[k] = o[k];
        row[o["kind"].toString()] = o["n"];
    }
    QVariantList out;
    for (auto &row : rows) {
        for (const char *k : {"litter", "food", "water"})
            if (!row.contains(k))
                row[k] = 0;
        out << row;
    }
    return out;
}

void Backend::refreshDone() {
    if (--m_refreshPending == 0 && m_refreshAgain) {
        m_refreshAgain = false;
        refresh();
    }
}

void Backend::refresh() {
    if (!m_connected)
        return;
    if (m_refreshPending > 0) {
        m_refreshAgain = true;
        return;
    }
    struct Job { QString path; QVariantList Backend::*target; QStringList pivotKeys; };
    const QList<Job> jobs{{"/api/today", &Backend::m_today, {"cat"}},
                          {"/api/stats?days=7", &Backend::m_week, {"day", "cat"}},
                          {"/api/recent?limit=300", &Backend::m_recent, {}},
                          {"/api/cameras", &Backend::m_cameras, {}},
                          {"/api/cats", &Backend::m_cats, {}}};
    m_refreshPending = int(jobs.size()) + 2;
    auto *st = get("/api/status");
    connect(st, &QNetworkReply::finished, this, [this, st] {
        st->deleteLater();
        if (st->error() == QNetworkReply::NoError) {
            m_status = QJsonDocument::fromJson(st->readAll()).object().toVariantMap();
            emit statusChanged();
        }
        refreshDone();
    });
    const qint64 midnight = QDateTime(QDate::currentDate(), QTime(0, 0)).toSecsSinceEpoch();
    auto *al = get(QString("/api/events?type=alert&since=%1").arg(midnight));
    connect(al, &QNetworkReply::finished, this, [this, al] {
        al->deleteLater();
        if (al->error() == QNetworkReply::NoError) {
            m_alertsToday = QJsonDocument::fromJson(al->readAll()).array().toVariantList();
            std::reverse(m_alertsToday.begin(), m_alertsToday.end());
            emit dataChanged();
        }
        refreshDone();
    });
    for (const auto &job : jobs) {
        auto *reply = get(job.path);
        connect(reply, &QNetworkReply::finished, this, [this, reply, job] {
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) {
                setError(tr("Sem conexão com o servidor"));
            } else {
                setError({});
                auto list = QJsonDocument::fromJson(reply->readAll()).array().toVariantList();
                if (!job.pivotKeys.isEmpty())
                    list = pivot(list, job.pivotKeys);
                if (job.path == "/api/stats?days=7")
                    std::reverse(list.begin(), list.end());  // dia mais recente primeiro
                this->*job.target = list;
                emit dataChanged();
            }
            refreshDone();
        });
    }
}

QString Backend::snapshotUrl(const QString &camera, double frame, bool raw) const {
    QUrl url(m_url + "/snapshot/" + enc(camera) + ".jpg");
    QUrlQuery q;
    q.addQueryItem("token", m_token);
    q.addQueryItem("t", QString::number(frame, 'f', 0));
    if (raw)
        q.addQueryItem("raw", "true");
    url.setQuery(q);
    return url.toString();
}

QString Backend::thumbUrl(const QString &cat, int revision) const {
    QUrl url(m_url + "/api/cats/" + enc(cat) + "/thumb");
    QUrlQuery q;
    q.addQueryItem("token", m_token);
    q.addQueryItem("r", QString::number(revision));
    url.setQuery(q);
    return url.toString();
}

QString Backend::photoUrl(int visitId) const {
    QUrl url(m_url + QString("/api/visits/%1/photo").arg(visitId));
    QUrlQuery q;
    q.addQueryItem("token", m_token);
    url.setQuery(q);
    return url.toString();
}

void Backend::fixVisit(int id, const QString &cat) {
    auto req = request(QString("/api/visits/%1").arg(id));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setTransferTimeout(60000);  // o servidor analisa as fotos da visita para aprender com elas
    auto *reply = m_net.sendCustomRequest(req, "PATCH", QJsonDocument(QJsonObject{{"cat", cat}}).toJson());
    connect(reply, &QNetworkReply::finished, this, [this, reply, cat] {
        const QByteArray body = reply->readAll();
        const int learned = QJsonDocument::fromJson(body).object().value("learned").toInt();
        // Sem erro: a mensagem diz se o Catwatch aprendeu com as fotos da câmera.
        finishAction(reply, learned > 0 ? tr("Visita de %1. %2 fotos desta câmera entraram no cadastro de %1.").arg(cat).arg(learned)
                                        : tr("Visita de %1").arg(cat), body);
    });
}

void Backend::deleteVisit(int id) { send("DELETE", QString("/api/visits/%1").arg(id)); }

void Backend::addCamera(const QString &name, const QString &source) {
    send("POST", "/api/cameras",
         QJsonDocument(QJsonObject{{"name", name.trimmed()}, {"source", source.trimmed()}}).toJson(),
         tr("Câmera %1 adicionada").arg(name.trimmed()));
}

void Backend::removeCamera(const QString &name) { send("DELETE", "/api/cameras/" + enc(name)); }

void Backend::setZones(const QString &camera, const QVariantList &zones) {
    send("PUT", "/api/cameras/" + enc(camera) + "/zones", QJsonDocument::fromVariant(zones).toJson(),
         tr("Zonas salvas"));
}

void Backend::addPhotos(const QString &cat, const QStringList &fileUrls) {
    for (const auto &u : fileUrls)
        m_queue.append({cat, QUrl(u).toLocalFile()});
    m_upTotal += fileUrls.size();
    m_upCat = cat;
    if (!m_uploading) {
        m_uploading = true;
        m_upDone = 0;
        m_upError.clear();
        nextUpload();
    }
    emit uploadChanged();
}

void Backend::nextUpload() {
    if (m_queue.isEmpty()) {
        const bool failed = !m_upError.isEmpty();
        const QString text = failed ? m_upError : tr("%1 fotos de %2 enviadas").arg(m_upDone).arg(m_upCat);
        m_uploading = false;
        m_upTotal = m_upDone = 0;
        ++m_catsRevision;
        emit uploadChanged();
        emit message(text, failed);
        refresh();
        return;
    }
    const Upload up = m_queue.takeFirst();
    auto *file = new QFile(up.path);
    if (!file->open(QIODevice::ReadOnly)) {
        if (m_upError.isEmpty())
            m_upError = tr("Não consegui abrir %1").arg(QFileInfo(up.path).fileName());
        delete file;
        ++m_upDone;
        emit uploadChanged();
        nextUpload();
        return;
    }
    auto *multi = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    QHttpPart part;
    part.setHeader(QNetworkRequest::ContentDispositionHeader,
                   "form-data; name=\"photo\"; filename=\"" + QFileInfo(up.path).fileName() + "\"");
    part.setHeader(QNetworkRequest::ContentTypeHeader, "image/jpeg");
    part.setBodyDevice(file);
    file->setParent(multi);
    multi->append(part);
    auto request2 = request("/api/cats/" + enc(up.cat) + "/photos");
    request2.setTransferTimeout(60000);  // o servidor roda a detecção em cada foto
    auto *reply = m_net.post(request2, multi);
    multi->setParent(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError && m_upError.isEmpty()) {
            const QString d = QJsonDocument::fromJson(reply->readAll()).object().value("detail").toString();
            m_upError = d.isEmpty() ? reply->errorString() : d;
        }
        ++m_upDone;
        emit uploadChanged();
        nextUpload();
    });
}

void Backend::catFromCamera(const QString &cat, const QString &camera) {
    send("POST", "/api/cats/" + enc(cat) + "/from-camera/" + enc(camera), {}, tr("Foto de %1 salva").arg(cat));
    ++m_catsRevision;
}

void Backend::deleteCat(const QString &cat) { send("DELETE", "/api/cats/" + enc(cat), {}, tr("%1 apagado").arg(cat)); }

bool Backend::isLocal() const {
    const QString host = QUrl(m_url).host();
    return host == "127.0.0.1" || host == "localhost" || host == "::1";
}

void Backend::pollEvents() {
    if (!m_connected || m_eventsBusy)
        return;
    m_eventsBusy = true;
    // Primeira carga: os últimos 200, sem notificar (são do passado). Depois: só os novos.
    auto *reply = get(m_eventsLoaded ? QString("/api/events?after=%1").arg(m_lastEventId)
                                     : QString("/api/events?limit=200"));
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        m_eventsBusy = false;
        if (reply->error() != QNetworkReply::NoError)
            return;
        const auto list = QJsonDocument::fromJson(reply->readAll()).array().toVariantList();
        if (list.isEmpty() && m_eventsLoaded)
            return;
        // Os mais novos primeiro, para a lista do log.
        for (const auto &v : list) {
            const auto e = v.toMap();
            m_lastEventId = std::max(m_lastEventId, e.value("id").toInt());
            m_events.prepend(e);
            if (m_eventsLoaded)
                emit newEvent(e);
        }
        while (m_events.size() > 300)
            m_events.removeLast();
        m_eventsLoaded = true;
        emit eventsChanged();
    });
}

void Backend::loadSettings() {
    auto *reply = get("/api/settings");
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() == QNetworkReply::NoError) {
            m_serverSettings = QJsonDocument::fromJson(reply->readAll()).object().toVariantMap();
            emit settingsChanged();
        }
    });
}

void Backend::saveSettings(const QVariantMap &changes) {
    auto req = request("/api/settings");
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    auto *reply = m_net.put(req, QJsonDocument::fromVariant(changes).toJson());
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        const auto body = QJsonDocument::fromJson(reply->readAll()).object();
        if (reply->error() != QNetworkReply::NoError) {
            const QString d = body.value("detail").toString();
            emit message(d.isEmpty() ? reply->errorString() : d, true);
            return;
        }
        m_serverSettings = body.value("settings").toObject().toVariantMap();
        emit settingsChanged();
        emit message(body.value("restart_required").toBool()
                         ? tr("Configurações salvas. Reinicie o servidor para aplicar a porta ou o processador.")
                         : tr("Configurações salvas e aplicadas"), false);
        refresh();
    });
}

void Backend::regenerateToken() {
    auto *reply = m_net.post(request("/api/token/regenerate"), QByteArray());
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit message(reply->errorString(), true);
            return;
        }
        m_token = QJsonDocument::fromJson(reply->readAll()).object().value("token").toString();
        m_settings.setValue("token", m_token);
        emit connectedChanged();
        emit message(tr("Token trocado. Celulares e outros PCs precisam conectar de novo."), false);
        loadPair();
    });
}

void Backend::loadPair() {
    auto *reply = get("/api/pair");
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() == QNetworkReply::NoError) {
            m_pair = QJsonDocument::fromJson(reply->readAll()).object().toVariantMap();
            ++m_pairRevision;
            emit pairChanged();
        }
    });
}

QString Backend::pairQrUrl(int revision) const {
    QUrl url(m_url + "/api/pair.png");
    QUrlQuery q;
    q.addQueryItem("token", m_token);
    q.addQueryItem("r", QString::number(revision));
    url.setQuery(q);
    return url.toString();
}

void Backend::download(const QString &path, const QString &fileUrl) {
    if (m_download)
        return;
    auto *file = new QSaveFile(QUrl(fileUrl).toLocalFile(), this);
    if (!file->open(QIODevice::WriteOnly)) {
        emit message(tr("Não consegui gravar em %1").arg(file->fileName()), true);
        delete file;
        return;
    }
    auto req = request(path);
    req.setTransferTimeout(10 * 60 * 1000);  // o backup pode ser grande
    m_download = m_net.get(req);
    m_downloadProgress = -1;
    emit downloadChanged();
    connect(m_download, &QNetworkReply::readyRead, this, [this, file] { file->write(m_download->readAll()); });
    connect(m_download, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
        m_downloadProgress = total > 0 ? int(got * 100 / total) : -1;
        emit downloadChanged();
    });
    connect(m_download, &QNetworkReply::finished, this, [this, file] {
        auto *reply = m_download;
        m_download = nullptr;
        reply->deleteLater();
        if (reply->error() == QNetworkReply::NoError) {
            file->write(reply->readAll());
            if (file->commit())  // grava ao lado e renomeia: nunca deixa um arquivo pela metade
                emit message(tr("Salvo em %1").arg(file->fileName()), false);
            else
                emit message(tr("Não consegui gravar em %1").arg(file->fileName()), true);
        } else {
            file->cancelWriting();
            emit message(reply->errorString(), true);
        }
        file->deleteLater();
        emit downloadChanged();
    });
}

void Backend::importBackup(const QString &fileUrl, bool withSettings) {
    if (m_import)
        return;
    auto *file = new QFile(QUrl(fileUrl).toLocalFile());
    if (!file->open(QIODevice::ReadOnly)) {
        emit message(tr("Não consegui abrir %1").arg(QFileInfo(*file).fileName()), true);
        delete file;
        return;
    }
    auto *multi = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    QHttpPart part;
    part.setHeader(QNetworkRequest::ContentDispositionHeader,
                   "form-data; name=\"backup\"; filename=\"" + QFileInfo(*file).fileName() + "\"");
    part.setHeader(QNetworkRequest::ContentTypeHeader, "application/zip");
    part.setBodyDevice(file);
    file->setParent(multi);
    multi->append(part);
    QHttpPart flag;
    flag.setHeader(QNetworkRequest::ContentDispositionHeader, "form-data; name=\"settings\"");
    flag.setBody(withSettings ? "true" : "false");
    multi->append(flag);

    auto req = request("/api/restore");
    req.setTransferTimeout(30 * 60 * 1000);  // backup grande + reanalisar a galeria dos gatos
    m_import = m_net.post(req, multi);
    multi->setParent(m_import);
    m_importProgress = 0;
    emit importChanged();
    connect(m_import, &QNetworkReply::uploadProgress, this, [this](qint64 sent, qint64 total) {
        // Arquivo todo enviado: daqui em diante é o servidor importando (sem como medir).
        m_importProgress = total > 0 && sent < total ? int(sent * 100 / total) : -1;
        emit importChanged();
    });
    connect(m_import, &QNetworkReply::finished, this, [this] {
        auto *reply = m_import;
        m_import = nullptr;
        reply->deleteLater();
        const auto body = QJsonDocument::fromJson(reply->readAll()).object();
        if (reply->error() == QNetworkReply::NoError) {
            // Sem catálogo de tradução, o %n do Qt não escolhe singular/plural; fazemos à mão.
            auto count = [](int n, const QString &one, const QString &many) { return QString("%1 %2").arg(n).arg(n == 1 ? one : many); };
            emit message(tr("Backup importado: %1, %2 e %3. Os dados anteriores ficaram em %4.")
                             .arg(count(body.value("visits").toInt(), tr("visita"), tr("visitas")),
                                  count(body.value("cats").toInt(), tr("gato"), tr("gatos")),
                                  count(body.value("cameras").toInt(), tr("câmera"), tr("câmeras")),
                                  body.value("safety_backup").toString()), false);
            ++m_catsRevision;
            refresh();
            loadSettings();
        } else {
            const QString d = body.value("detail").toString();
            emit message(d.isEmpty() ? reply->errorString() : d, true);
        }
        emit importChanged();
    });
}
