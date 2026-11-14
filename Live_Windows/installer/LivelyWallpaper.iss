; ==============================================================================
; Live_Windows/installer/LivelyWallpaper.iss
; Inno Setup Script for Lively Wallpaper Windows (with Flake Snow Mode)
; ==============================================================================

#define MyAppName "Lively Wallpaper"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Lively Wallpaper Contributors"
#define MyAppURL "https://github.com/youssefdawood197/Live_Mac"
#define MyAppExeName "Live.App.exe"
#define MyPublishDir "..\src\Live.App\bin\Release\net8.0-windows10.0.19041.0\win-x64\publish"

[Setup]
AppId={{9B7E31D6-8E31-4A2D-A483-C7B3AE58D8B2}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\bin\installer
OutputBaseFilename=LivelyWallpaper-Windows-Setup-x64
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startupicon"; Description: "Launch Lively Wallpaper on Windows startup"; GroupDescription: "Startup Options:"

[Files]
Source: "{#MyPublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
