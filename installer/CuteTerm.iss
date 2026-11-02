; CuteTerm Windows-only, per-user installer. Built by GitHub Actions using Inno Setup.
#define MyAppName "CuteTerm"
#define MyAppVersion "0.4.0"
#define MyAppPublisher "taithedev"
#define MyAppURL "https://github.com/taithedev/Cuteterm"

[Setup]
AppId={{F0CCF87A-FD71-4ED4-95BF-EA56818DEAE9}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases/latest
AppSupportURL={#MyAppURL}/issues
DefaultDirName={localappdata}\Programs\CuteTerm
DefaultGroupName=CuteTerm
PrivilegesRequired=lowest
DisableDirPage=yes
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
OutputDir=Output
OutputBaseFilename=CuteTerm-Windows-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription=CuteTerm Windows CLI Installer
UninstallDisplayName=CuteTerm
CloseApplications=no
RestartApplications=no
ChangesEnvironment=yes
SetupLogging=yes

[Files]
Source: "..\install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\cli\start.ps1"; DestDir: "{app}\cli"; Flags: ignoreversion
Source: "..\cli\cli.ps1"; DestDir: "{app}\cli"; Flags: ignoreversion
Source: "..\cli\version.txt"; DestDir: "{app}\cli"; Flags: ignoreversion
Source: "..\cli\commands\*"; DestDir: "{app}\cli\commands"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\cli\module\*"; DestDir: "{app}\cli\module"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\cli\lib\*"; DestDir: "{app}\cli\lib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\cli\themes\*"; DestDir: "{app}\cli\themes"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\cli\updater\*"; DestDir: "{app}\cli\updater"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\cli\docs\*"; DestDir: "{app}\cli\docs"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\cli\examples\*"; DestDir: "{app}\cli\examples"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\CuteTerm"; Filename: "{localappdata}\CuteTerm\bin\cuteterm.cmd"; WorkingDir: "{localappdata}"; Comment: "CuteTerm PowerShell CLI"

[Run]
Filename: "pwsh.exe"; Parameters: "-NoLogo -NoProfile -NonInteractive -File ""{app}\install.ps1"""; WorkingDir: "{app}"; StatusMsg: "Configuring CuteTerm CLI and Windows Terminal..."; Flags: runhidden waituntilterminated

[UninstallRun]
Filename: "pwsh.exe"; Parameters: "-NoLogo -NoProfile -NonInteractive -File ""{app}\uninstall.ps1"" -Force"; WorkingDir: "{app}"; Flags: runhidden waituntilterminated

[Code]
function InitializeSetup(): Boolean;
var
  Code: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'),
    '/D /C where pwsh.exe >nul 2>nul', '',
    SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
  if not Result then
    MsgBox('CuteTerm requires PowerShell 7 or newer.' + #13#10 + 'Install it first with: winget install --id Microsoft.PowerShell -e' + #13#10 + 'Then reopen this installer.', mbError, MB_OK);
end;
