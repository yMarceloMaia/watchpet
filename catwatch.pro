QT += core gui qml quick quickcontrols2 network widgets
CONFIG += c++17 release
TARGET = catwatch
TEMPLATE = app

HEADERS += src/backend.h src/theme.h src/servermanager.h src/shell.h
SOURCES += src/main.cpp src/backend.cpp src/theme.cpp src/servermanager.cpp src/shell.cpp
RESOURCES += src/resources.qrc
