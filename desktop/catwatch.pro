QT += core gui qml quick quickcontrols2 network widgets svg
CONFIG += c++17 release
TARGET = catwatch
TEMPLATE = app

HEADERS += src/backend.h src/theme.h src/servermanager.h src/shell.h
SOURCES += src/main.cpp src/backend.cpp src/theme.cpp src/servermanager.cpp src/shell.cpp
RESOURCES += src/resources.qrc

# Windows: ícone do .exe e o Job Object que encerra o servidor junto com o app.
win32 {
    RC_ICONS = windows/catwatch.ico
    QMAKE_TARGET_DESCRIPTION = Catwatch
    VERSION = 1.2.0
}
