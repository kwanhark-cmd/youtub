; 윈도우 설치 프로그램(Inno Setup). GitHub Actions에서 자동으로 만든다.
#define MyAppName "하드 자료 찾기 비서"
#define MyAppVersion "1.1.0"
[Setup]
AppId={{6C1E2F7A-3B5D-4C55-9E21-HDBISEO00001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\HDBiseo
DefaultGroupName={#MyAppName}
OutputDir=dist
OutputBaseFilename=HDBiseo-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
; 업데이트 = 같은 AppId로 덮어쓰기. 프로그램 파일만 바꾸고, 자료 폴더(%LOCALAPPDATA%\HDBiseo)는 건드리지 않는다.
UsePreviousAppDir=yes
UsePreviousTasks=yes
CloseApplications=force
RestartApplications=no
DisableDirPage=auto
DisableProgramGroupPage=auto
[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
[Tasks]
Name: "desktopicon"; Description: "바탕화면에 아이콘 만들기"; Flags: checkedonce
Name: "autostart"; Description: "컴퓨터를 켤 때 자동으로 시작(밤 색인용)"
[Files]
Source: "dist\HDBiseo\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\HDBiseo.exe"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\HDBiseo.exe"; Tasks: desktopicon
[Registry]
; PC 시작 시 자동 실행(앱 설정 화면의 켜기/끄기와 같은 이름 'HDBiseo')
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "HDBiseo"; ValueData: """{app}\HDBiseo.exe"" --no-browser"; Tasks: autostart; Flags: uninsdeletevalue
[InstallDelete]
; 1.0.0의 시작 프로그램 바로가기(같은 일을 하는 옛 방식)만 정리. 사용자 자료는 지우지 않음
Type: files; Name: "{userstartup}\{#MyAppName}.lnk"
[Run]
; 조용한 설치(앱 안 업데이트)일 때도 끝나면 다시 켜짐(skipifsilent 없음)
Filename: "{app}\HDBiseo.exe"; Description: "지금 실행"; Flags: nowait postinstall
