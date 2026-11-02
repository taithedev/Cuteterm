; CuteTerm — native Rust CLI, Windows x64, per-user installer. No PowerShell required.
#define MyAppName "CuteTerm"
#define MyAppVersion "0.6.1"
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
ArchitecturesAllowed=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription=CuteTerm Rust-native Windows CLI
UninstallDisplayName=CuteTerm
CloseApplications=force
RestartApplications=no
ChangesEnvironment=yes
SetupLogging=yes

[InstallDelete]
; Remove old experimental PowerShell CLI runtime files. Leave user AppData alone.
Type: filesandordirs; Name: "{app}\cli"
Type: files; Name: "{app}\install.ps1"
Type: files; Name: "{app}\uninstall.ps1"

[Files]
Source: "..\target\release\cuteterm.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\target\release\cuteterm-updater.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\commands\*.json"; DestDir: "{app}\commands"; Flags: ignoreversion
Source: "..\terminal\CuteTerm.json"; DestDir: "{localappdata}\Microsoft\Windows Terminal\Fragments\CuteTerm"; Flags: ignoreversion


[Tasks]
Name: "explorer"; Description: "Add Open CuteTerm Here to File Explorer"; Flags: unchecked

[Registry]
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\CuteTerm"; ValueType: string; ValueData: "Open CuteTerm Here"; Tasks: explorer; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\CuteTerm\command"; ValueType: string; ValueData: """{app}\cuteterm.exe"" --cwd ""%V"""; Tasks: explorer; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\CuteTerm"; ValueType: string; ValueData: "Open CuteTerm Here"; Tasks: explorer; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\CuteTerm\command"; ValueType: string; ValueData: """{app}\cuteterm.exe"" --cwd ""%1"""; Tasks: explorer; Flags: uninsdeletekey

[Icons]
Name: "{userprograms}\CuteTerm"; Filename: "{app}\cuteterm.exe"; WorkingDir: "{localappdata}"; Comment: "Native Rust terminal workbench"
Name: "{userprograms}\CuteTerm - Command List"; Filename: "{app}\cuteterm.exe"; Parameters: "commands"; WorkingDir: "{localappdata}"; Comment: "Show real installed commands"

[Run]
Filename: "{app}\cuteterm.exe"; Description: "Launch CuteTerm"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: files; Name: "{localappdata}\Microsoft\Windows Terminal\Fragments\CuteTerm\CuteTerm.json"

[Code]
function HasPathSegment(PathValue, Segment: String): Boolean;
begin
  Result := Pos(';' + Lowercase(Segment) + ';', ';' + Lowercase(PathValue) + ';') > 0;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  OldPath, AppPath: String;
begin
  if CurStep = ssPostInstall then begin
    AppPath := ExpandConstant('{app}');
    if not RegQueryStringValue(HKCU, 'Environment', 'Path', OldPath) then
      OldPath := '';
    if not HasPathSegment(OldPath, AppPath) then begin
      if OldPath = '' then
        OldPath := AppPath
      else
        OldPath := OldPath + ';' + AppPath;
      RegWriteExpandStringValue(HKCU, 'Environment', 'Path', OldPath);
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  OldPath, AppPath, UpdatedPath: String;
begin
  if CurUninstallStep = usPostUninstall then begin
    AppPath := ExpandConstant('{app}');
    if RegQueryStringValue(HKCU, 'Environment', 'Path', OldPath) then begin
      UpdatedPath := ';' + OldPath + ';';
      StringChangeEx(UpdatedPath, ';' + AppPath + ';', ';', True);
      if (Length(UpdatedPath) >= 2) and (UpdatedPath[1] = ';') then
        Delete(UpdatedPath, 1, 1);
      if (Length(UpdatedPath) >= 1) and (UpdatedPath[Length(UpdatedPath)] = ';') then
        Delete(UpdatedPath, Length(UpdatedPath), 1);
      if UpdatedPath <> OldPath then
        RegWriteExpandStringValue(HKCU, 'Environment', 'Path', UpdatedPath);
    end;
  end;
end;
