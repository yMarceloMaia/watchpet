#include "backend.h"

#include <QFile>
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
    m_frames.setInterval(800);
    connect(&m_frames, &QTimer::timeout, this, [this] { ++m_frame; emit frameChanged(); });

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
void Backend::finishAction(QNetworkReply *reply, const QString &okText) {
    reply->deleteLater();
    if (reply->error() == QNetworkReply::NoError) {
        if (!okText.isEmpty())
            emit message(okText, false);
    } else {
        const QString detail = QJsonDocument::fromJson(reply->readAll()).object().value("detail").toString();
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
            emit connectedChanged();
            m_poll.start();
            m_frames.start();
            refresh();
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
    m_frames.stop();
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

void Backend::refresh() {
    if (!m_connected)
        return;
    struct Job { QString path; QVariantList Backend::*target; QStringList pivotKeys; };
    const QList<Job> jobs{{"/api/today", &Backend::m_today, {"cat"}},
                          {"/api/stats?days=7", &Backend::m_week, {"day", "cat"}},
                          {"/api/recent?limit=100", &Backend::m_recent, {}},
                          {"/api/cameras", &Backend::m_cameras, {}},
                          {"/api/cats", &Backend::m_cats, {}}};
    for (const auto &job : jobs) {
        auto *reply = get(job.path);
        connect(reply, &QNetworkReply::finished, this, [this, reply, job] {
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) {
                setError(tr("Sem conexão com o servidor"));
                return;
            }
            setError({});
            auto list = QJsonDocument::fromJson(reply->readAll()).array().toVariantList();
            if (!job.pivotKeys.isEmpty())
                list = pivot(list, job.pivotKeys);
            if (job.path == "/api/stats?days=7")
                std::reverse(list.begin(), list.end());  // dia mais recente primeiro
            this->*job.target = list;
            emit dataChanged();
        });
    }
}

QString Backend::snapshotUrl(const QString &camera, int frame, bool raw) const {
    QUrl url(m_url + "/snapshot/" + enc(camera) + ".jpg");
    QUrlQuery q;
    q.addQueryItem("token", m_token);
    q.addQueryItem("t", QString::number(frame));
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
    send("PATCH", QString("/api/visits/%1").arg(id), QJsonDocument(QJsonObject{{"cat", cat}}).toJson(),
         tr("Visita atribuída a %1").arg(cat));
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
