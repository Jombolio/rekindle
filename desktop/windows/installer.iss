#define AppName "Rekindle"
#define AppVersion "1.5.1-beta.6"
#define AppExeName "rekindle.exe"
#define AppURL "https://git.jombo.uk/Jombo/rekindle"

[Setup]
AppId={{A3F2C1D4-8B7E-4F2A-9C6D-1E5B3A7F8D2C}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisherURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=output
OutputBaseFilename=Rekindle-windows-x64Setup
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: desktopicon; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; \
  DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";           Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#AppName}";   Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; \
  Description: "Launch {#AppName}"; \
  Flags: nowait postinstall skipifsilent
; In-app updates run this installer with /SILENT, which skips the entry
; above, so relaunch Rekindle here. runasoriginaluser: the installer is
; elevated, and the app must run as the user (their settings live in their
; profile), not as the admin account that approved the install.
Filename: "{app}\{#AppExeName}"; \
  Flags: nowait runasoriginaluser; \
  Check: WizardSilent
