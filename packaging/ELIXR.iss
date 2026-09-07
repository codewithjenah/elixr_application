#define MyAppName "ELIXR"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\pilot\staging"
#endif
#ifndef OutputDir
  #define OutputDir "..\build\pilot"
#endif

[Setup]
AppId={{A8A0C3EA-52D7-4AB3-AE4B-202609070001}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher=ELIXR
DefaultDirName={localappdata}\Programs\ELIXR
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=ELIXR_Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\elixr_application.exe

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\elixr_application.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\elixr_application.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\elixr_application.exe"; Description: "Launch {#MyAppName}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
