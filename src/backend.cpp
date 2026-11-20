#include "backend.h"

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
    // Os quadros das câmeras só são buscados enquanto a tela de câmeras está visível (Image em QML).
    m_frames.setInterval(800);
    connect(&m_frames, &QTimer::timeout, this, [this] { ++m_frame; emit frameChanged(); });

    const QString url = savedUrl(), token = savedToken();
    if (!url.isEmpty() && !token.isEmpty())
        connectTo(url, token);
}

QNetworkReply *Backend::get(const QString &path) {
    QNetworkRequest req(QUrl(m_url + path));
    req.setRawHeader("X-Token", m_token.toUtf8());
    req.setTransferTimeout(8000);
    return m_net.get(req);
}

void Backend::send(const QString &method, const QString &path, const QByteArray &body) {
    QNetworkRequest req(QUrl(m_url + path));
    req.setRawHeader("X-Token", m_token.toUtf8());
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    auto *reply = m_net.sendCustomRequest(req, method.toUtf8(), body);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        refresh();
    });
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

QVariantList Backend::pivot(const QVariantList &counts) {
    QMap<QString, QVariantMap> byCat;
    for (const auto &v : counts) {
        const auto o = v.toMap();
        auto &row = byCat[o["cat"].toString()];
        row["cat"] = o["cat"];
        row[o["kind"].toString()] = o["n"];
    }
    QVariantList out;
    for (auto &row : byCat) {
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
    struct Job { QString path; QVariantList Backend::*target; bool pivot; };
    const QList<Job> jobs{{"/api/today", &Backend::m_today, true},
                          {"/api/recent?limit=100", &Backend::m_recent, false},
                          {"/api/cameras", &Backend::m_cameras, false}};
    for (const auto &job : jobs) {
        auto *reply = get(job.path);
        connect(reply, &QNetworkReply::finished, this, [this, reply, job] {
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) {
                setError(tr("Sem conexão com o servidor"));
                return;
            }
            setError({});
            const auto list = QJsonDocument::fromJson(reply->readAll()).array().toVariantList();
            this->*job.target = job.pivot ? pivot(list) : list;
            emit dataChanged();
        });
    }
}

QString Backend::snapshotUrl(const QString &camera, int frame) const {
    // O token vai na query porque o QML Image não consegue mandar cabeçalhos.
    QUrl url(m_url + "/snapshot/" + QString::fromUtf8(QUrl::toPercentEncoding(camera)) + ".jpg");
    QUrlQuery q;
    q.addQueryItem("token", m_token);
    q.addQueryItem("t", QString::number(frame));
    url.setQuery(q);
    return url.toString();
}

void Backend::fixVisit(int id, const QString &cat) {
    send("PATCH", QString("/api/visits/%1").arg(id), QJsonDocument(QJsonObject{{"cat", cat}}).toJson());
}

void Backend::deleteVisit(int id) { send("DELETE", QString("/api/visits/%1").arg(id)); }

void Backend::removeCamera(const QString &name) {
    send("DELETE", "/api/cameras/" + QString::fromUtf8(QUrl::toPercentEncoding(name)));
}
