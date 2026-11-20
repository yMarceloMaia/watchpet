#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>

// Segue o accent do tema do Omarchy ao vivo (padrão do Omacut, MIT, David Heinemeier Hansson).
class Theme : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString accent READ accent NOTIFY changed)
    Q_PROPERTY(QString accentForeground READ accentForeground NOTIFY changed)
    // Tema claro do Omarchy (mode = "light" no colors.toml).
    Q_PROPERTY(bool light READ light NOTIFY changed)
    Q_PROPERTY(int radius READ radius CONSTANT)

public:
    explicit Theme(const QString &currentDirectory = {}, QObject *parent = nullptr);

    QString accent() const { return m_accent; }
    QString accentForeground() const;
    bool light() const { return m_light; }
    int radius() const { return 0; }  // cantos retos, como o padrão do Omarchy

    static QString readAccent(const QString &path);
    static bool readLight(const QString &path);

signals:
    void changed();

private:
    void reload();

    QString m_directory;
    QString m_accent = "#FFD60A";
    bool m_light = false;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};
