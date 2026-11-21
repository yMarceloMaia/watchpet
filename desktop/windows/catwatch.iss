; Instalador do Catwatch para Windows (Inno Setup 6): app de PC + servidor embutido.
; Gerado pelo GitHub Actions (.github/workflows/windows.yml):
;   ISCC /DAppVersion=1.2.0 /DSource=<pasta montada> /DOutput=<saída> catwatch.iss
; A pasta montada tem o app (catwatch.exe + Qt) e, em server\, o catwatch-server.exe.
;
; Instala para o usuário (sem pedir administrador) em %LOCALAPPDATA%\Programs\Catwatch.
; Os dados (gatos, histórico, fotos) ficam em %LOCALAPPDATA%\Catwatch e não são apagados
; ao desinstalar.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Source
  #define Source "..\..\stage"
#endif
#ifndef Output
  #define Output "."
#endif

[Setup]
AppId={{B9ECCAEF-B500-443E-85E7-B170D50B65AF}
AppName=Catwatch
AppVersion={#AppVersion}
AppVerName=Catwatch {#AppVersion}
AppPublisher=watchpet
AppPublisherURL=https://github.com/yMarceloMaia/watchpet
DefaultDirName={localappdata}\Programs\Catwatch
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#Output}
OutputBaseFilename=catwatch-setup-{#AppVersion}
SetupIconFile=catwatch.ico
UninstallDisplayIcon={app}\catwatch.exe
UninstallDisplayName=Catwatch
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Atualizar com o app aberto: o instalador pede para fechá-lo antes de trocar os arquivos.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "startup"; Description: "Abrir o Catwatch ao entrar no Windows (fica na bandeja e monitora os gatos)"
Name: "desktopicon"; Description: "Criar um atalho na área de trabalho"; Flags: unchecked

[Files]
Source: "{#Source}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Catwatch"; Filename: "{app}\catwatch.exe"
Name: "{autodesktop}\Catwatch"; Filename: "{app}\catwatch.exe"; Tasks: desktopicon

[Registry]
; Mesmo valor que o app grava em Servidor > "Iniciar com o sistema".
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Catwatch"; ValueData: """{app}\catwatch.exe"" --background"; Flags: uninsdeletevalue; Tasks: startup
; Ao desinstalar, remove o valor mesmo se foi o app (e não o instalador) que o criou.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Catwatch"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\catwatch.exe"; Description: "Abrir o Catwatch agora"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; O app e o servidor precisam estar fechados para os arquivos saírem.
Filename: "{sys}\taskkill.exe"; Parameters: "/IM catwatch.exe /F"; Flags: runhidden; RunOnceId: "FecharCatwatch"
Filename: "{sys}\taskkill.exe"; Parameters: "/IM catwatch-server.exe /F"; Flags: runhidden; RunOnceId: "FecharServidor"
