; AFloat - 安装器

#define MyAppName "AFloat"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "SmartEnglish"
#define MyAppExeName "afloat.exe"
#define MyAppURL "https://github.com"
#define BuildDir "..\build\windows\x64\runner\Release"
#define IconFile "..\windows\runner\resources\app_icon.ico"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=.\output
OutputBaseFilename=afloat-setup
SetupIconFile={#IconFile}
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[CustomMessages]
chinesesimplified.CreateDesktopIcon=创建桌面快捷方式
chinesesimplified.AdditionalIcons=附加图标:
chinesesimplified.LaunchProgram=立即启动 [name]
chinesesimplified.UninstallProgram=卸载 [name]

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\dartjni.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\flutter_tts_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\desktop_drop_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\screen_retriever_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\window_manager_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
