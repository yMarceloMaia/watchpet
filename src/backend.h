#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QSettings>
#include <QTimer>
#include <QVariantList>

// Cliente fino do servidor Catwatch: só busca JSON e imagens; toda a IA roda no servidor.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QString serverUrl READ serverUrl NOTIFY connectedChanged)
    Q_PROPERTY(QVariantList today READ today NOTIFY dataChanged)
    Q_PROPERTY(QVariantList recent READ recent NOTIFY dataChanged)
    Q_PROPERTY(QVariantList cameras READ cameras NOTIFY dataChanged)
    Q_PROPERTY(int frame READ frame NOTIFY frameChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    bool connected() const { return m_connected; }
    QString error() const { return m_error; }
    QString serverUrl() const { return m_url; }
    QVariantList today() const { return m_today; }
    QVariantList recent() const { return m_recent; }
    QVariantList cameras() const { return m_cameras; }
    int frame() const { return m_frame; }

    Q_INVOKABLE void connectTo(const QString &url, const QString &token);
    Q_INVOKABLE void disconnectServer();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE QString snapshotUrl(const QString &camera, int frame) const;
    Q_INVOKABLE QString savedUrl() const { return m_settings.value("url").toString(); }
    Q_INVOKABLE QString savedToken() const { return m_settings.value("token").toString(); }
    Q_INVOKABLE void fixVisit(int id, const QString &cat);
    Q_INVOKABLE void deleteVisit(int id);

    // Resume as contagens do dia em uma linha por gato (litter/food/water), para a tela "Hoje".
    static QVariantList pivot(const QVariantList &counts);

signals:
    void connectedChanged();
    void errorChanged();
    void dataChanged();
    void frameChanged();

private:
    QNetworkReply *get(const QString &path);
    void setError(const QString &e);
    void send(const QString &method, const QString &path, const QByteArray &body = {});

    QNetworkAccessManager m_net;
    QSettings m_settings;
    QTimer m_poll, m_frames;
    QString m_url, m_token, m_error;
    bool m_connected = false;
    int m_frame = 0;
    QVariantList m_today, m_recent, m_cameras;
};
