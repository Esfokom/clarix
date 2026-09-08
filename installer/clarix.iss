#define AppName "Clarix"
#define AppVersion GetEnv("CLARIX_APP_VERSION")
#define SourceDir GetEnv("CLARIX_RELEASE_DIR")

[Setup]
AppId={{F6D9E576-1DAE-4D8A-AC7A-95AFB37D08F9}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Clarix
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=Clarix-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\clarix.exe

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\clarix.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\clarix.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\clarix.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
