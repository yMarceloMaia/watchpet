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
    Q_PROPERTY(int catsRevision READ catsRevision NOTIFY dataChanged)
    Q_PROPERTY(bool uploading READ uploading NOTIFY uploadChanged)
    Q_PROPERTY(int uploadTotal READ uploadTotal NOTIFY uploadChanged)
    Q_PROPERTY(int uploadDone READ uploadDone NOTIFY uploadChanged)
    Q_PROPERTY(QString uploadCat READ uploadCat NOTIFY uploadChanged)
    Q_PROPERTY(QString token READ token NOTIFY connectedChanged)
    Q_PROPERTY(bool isLocal READ isLocal NOTIFY connectedChanged)
    Q_PROPERTY(QVariantMap status READ status NOTIFY statusChanged)
    Q_PROPERTY(QVariantList events READ events NOTIFY eventsChanged)
    Q_PROPERTY(QVariantList alertsToday READ alertsToday NOTIFY dataChanged)
    Q_PROPERTY(QVariantMap settings READ settings NOTIFY settingsChanged)
    Q_PROPERTY(QVariantMap pair READ pair NOTIFY pairChanged)
    Q_PROPERTY(int pairRevision READ pairRevision NOTIFY pairChanged)
    Q_PROPERTY(bool downloading READ downloading NOTIFY downloadChanged)
    Q_PROPERTY(int downloadProgress READ downloadProgress NOTIFY downloadChanged)
    Q_PROPERTY(bool importing READ importing NOTIFY importChanged)
    // 0 a 100 enquanto envia o arquivo; -1 quando o servidor já recebeu e está importando.
    Q_PROPERTY(int importProgress READ importProgress NOTIFY importChanged)

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
    int catsRevision() const { return m_catsRevision; }
    bool uploading() const { return m_uploading; }
    int uploadTotal() const { return m_upTotal; }
    int uploadDone() const { return m_upDone; }
    QString uploadCat() const { return m_upCat; }
    QString token() const { return m_token; }
    bool isLocal() const;
    QVariantMap status() const { return m_status; }
    QVariantList events() const { return m_events; }
    QVariantList alertsToday() const { return m_alertsToday; }
    QVariantMap settings() const { return m_serverSettings; }
    QVariantMap pair() const { return m_pair; }
    int pairRevision() const { return m_pairRevision; }
    bool downloading() const { return m_download != nullptr; }
    int downloadProgress() const { return m_downloadProgress; }
    bool importing() const { return m_import != nullptr; }
    int importProgress() const { return m_importProgress; }

    // Aba Servidor
    Q_INVOKABLE void loadSettings();
    Q_INVOKABLE void saveSettings(const QVariantMap &changes);
    Q_INVOKABLE void regenerateToken();
    Q_INVOKABLE void loadPair();
    Q_INVOKABLE QString pairQrUrl(int revision) const;
    // Baixa um arquivo do servidor (CSV, backup) direto para o caminho escolhido.
    Q_INVOKABLE void download(const QString &path, const QString &fileUrl);
    // Envia um backup .zip ao servidor, que substitui gatos, histórico e fotos (e, com
    // withSettings, câmeras e configurações). O servidor guarda antes uma cópia do que havia.
    Q_INVOKABLE void importBackup(const QString &fileUrl, bool withSettings);

    Q_INVOKABLE void connectTo(const QString &url, const QString &token);
    Q_INVOKABLE void disconnectServer();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE QString savedUrl() const { return m_settings.value("url").toString(); }
    Q_INVOKABLE QString savedToken() const { return m_settings.value("token").toString(); }

    // Imagens: o token vai na query porque o QML Image não consegue mandar cabeçalhos.
    // `frame` só muda a URL, para o QML não reaproveitar o quadro anterior.
    Q_INVOKABLE QString snapshotUrl(const QString &camera, double frame, bool raw = false) const;
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
    void uploadChanged();
    void statusChanged();
    void eventsChanged();
    void settingsChanged();
    void pairChanged();
    void downloadChanged();
    void importChanged();
    // Evento novo do servidor (depois da carga inicial), para virar notificação.
    void newEvent(const QVariantMap &event);    // Resultado de uma ação do usuário (sucesso ou o motivo da falha), para mostrar na janela.
    void message(const QString &text, bool isError);

private:
    QNetworkReply *get(const QString &path);
    QNetworkRequest request(const QString &path) const;
    void setError(const QString &e);
    void nextUpload();
    void pollEvents();
    void refreshDone();
    void finishAction(QNetworkReply *reply, const QString &okText);
    void send(const QString &method, const QString &path, const QByteArray &body = {}, const QString &okText = {});
    static QString enc(const QString &s) { return QString::fromUtf8(QUrl::toPercentEncoding(s)); }

    QNetworkAccessManager m_net;
    QSettings m_settings;
    QTimer m_poll;
    QString m_url, m_token, m_error;
    bool m_connected = false;
    int m_catsRevision = 0;
    // Pedidos de refresh() ainda sem resposta. Com o servidor lento, o relógio não empilha
    // outra rodada por cima; um refresh pedido nesse meio tempo roda quando ela termina.
    int m_refreshPending = 0;
    bool m_refreshAgain = false;
    // Um pedido de eventos por vez: dois ao mesmo tempo traziam os mesmos eventos novos,
    // que apareciam duas vezes no log e viravam notificações repetidas.
    bool m_eventsBusy = false;
    QVariantList m_today, m_week, m_recent, m_cameras, m_cats;

    // Fila de envio de fotos: uma por vez, para o progresso andar foto a foto e o servidor não engasgar.
    struct Upload { QString cat, path; };
    QList<Upload> m_queue;
    bool m_uploading = false;
    int m_upTotal = 0, m_upDone = 0;
    QString m_upCat, m_upError;

    QTimer m_eventsPoll;
    int m_lastEventId = 0;
    bool m_eventsLoaded = false;
    QVariantMap m_status, m_serverSettings, m_pair;
    QVariantList m_events, m_alertsToday;
    int m_pairRevision = 0;
    QNetworkReply *m_download = nullptr;
    int m_downloadProgress = -1;
    QNetworkReply *m_import = nullptr;
    int m_importProgress = 0;
};
