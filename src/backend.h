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
    Q_PROPERTY(QVariantList week READ week NOTIFY dataChanged)
    Q_PROPERTY(QVariantList recent READ recent NOTIFY dataChanged)
    Q_PROPERTY(QVariantList cameras READ cameras NOTIFY dataChanged)
    Q_PROPERTY(QVariantList cats READ cats NOTIFY dataChanged)
    Q_PROPERTY(int frame READ frame NOTIFY frameChanged)
    Q_PROPERTY(int catsRevision READ catsRevision NOTIFY dataChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    bool connected() const { return m_connected; }
    QString error() const { return m_error; }
    QString serverUrl() const { return m_url; }
    QVariantList today() const { return m_today; }
    QVariantList week() const { return m_week; }
    QVariantList recent() const { return m_recent; }
    QVariantList cameras() const { return m_cameras; }
    QVariantList cats() const { return m_cats; }
    int frame() const { return m_frame; }
    int catsRevision() const { return m_catsRevision; }

    Q_INVOKABLE void connectTo(const QString &url, const QString &token);
    Q_INVOKABLE void disconnectServer();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE QString savedUrl() const { return m_settings.value("url").toString(); }
    Q_INVOKABLE QString savedToken() const { return m_settings.value("token").toString(); }

    // Imagens: o token vai na query porque o QML Image não consegue mandar cabeçalhos.
    Q_INVOKABLE QString snapshotUrl(const QString &camera, int frame, bool raw = false) const;
    Q_INVOKABLE QString thumbUrl(const QString &cat, int revision) const;
    Q_INVOKABLE QString photoUrl(int visitId) const;

    // Histórico
    Q_INVOKABLE void fixVisit(int id, const QString &cat);
    Q_INVOKABLE void deleteVisit(int id);

    // Câmeras e zonas (zones: lista de {name, kind, polygon:[[x,y],...]} com coordenadas de 0 a 1)
    Q_INVOKABLE void addCamera(const QString &name, const QString &source);
    Q_INVOKABLE void removeCamera(const QString &name);
    Q_INVOKABLE void setZones(const QString &camera, const QVariantList &zones);

    // Gatos
    Q_INVOKABLE void addPhotos(const QString &cat, const QStringList &fileUrls);
    Q_INVOKABLE void catFromCamera(const QString &cat, const QString &camera);
    Q_INVOKABLE void deleteCat(const QString &cat);

    // Uma linha por gato (e por dia) com as contagens litter/food/water.
    static QVariantList pivot(const QVariantList &counts, const QStringList &keys);

signals:
    void connectedChanged();
    void errorChanged();
    void dataChanged();
    void frameChanged();
    // Resultado de uma ação do usuário (sucesso ou o motivo da falha), para mostrar na janela.
    void message(const QString &text, bool isError);

private:
    QNetworkReply *get(const QString &path);
    QNetworkRequest request(const QString &path) const;
    void setError(const QString &e);
    void finishAction(QNetworkReply *reply, const QString &okText);
    void send(const QString &method, const QString &path, const QByteArray &body = {}, const QString &okText = {});
    static QString enc(const QString &s) { return QString::fromUtf8(QUrl::toPercentEncoding(s)); }

    QNetworkAccessManager m_net;
    QSettings m_settings;
    QTimer m_poll, m_frames;
    QString m_url, m_token, m_error;
    bool m_connected = false;
    int m_frame = 0, m_catsRevision = 0;
    QVariantList m_today, m_week, m_recent, m_cameras, m_cats;
};
