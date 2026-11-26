# 한 번만 실행해요. 에뮬레이터에 필요한 것을 받아서 이 폴더 안에 깔아요. (약 2GB 내려받음, 설치 뒤 약 8GB)
. "$PSScriptRoot\common.ps1"

Say '갓바이블 QA 에뮬레이터 설치를 시작해요.'

# 0. 환경 확인
if (-not [Environment]::Is64BitOperatingSystem) { Fail '64비트 윈도우가 필요해요.' }
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { Fail 'ARM 윈도우 PC는 이 설치로는 안 돼요. 담당자에게 알려 주세요.' }
if ($Root -match '[^\x00-\x7F]' -or $Root -match '\s') {
  Warn ('설치 폴더 경로에 한글이나 띄어쓰기가 있어요: ' + $Root)
  Warn '에뮬레이터가 켜지지 않을 수 있어요. C:\godbible-emulator 처럼 영문 경로로 옮긴 뒤 다시 실행하는 것을 권해요.'
  $a = Read-Host '그래도 계속할까요? (y/n)'
  if ($a -ne 'y') { exit 1 }
}
$drive = (Get-Item $Root).PSDrive
if ($drive.Free -lt 12GB) { Warn ('디스크 여유 공간이 12GB보다 적어요. 지금 ' + [math]::Round($drive.Free / 1GB, 1) + 'GB') }

New-Item -ItemType Directory -Force -Path $Sdk, $AvdHome, $EmuHome, $Dl, $Out | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Sdk 'platforms') | Out-Null

# 1. 받을 것 (맥에서 쓰던 것과 같은 판. 주소는 구글 공식 저장소)
$items = @(
  @{ name = 'platform-tools (adb)'; url = 'https://dl.google.com/android/repository/platform-tools_r37.0.1-win.zip'; file = 'platform-tools_r37.0.1-win.zip'; size = 8044989 },
  @{ name = '에뮬레이터';            url = 'https://dl.google.com/android/repository/emulator-windows_x64-16740729.zip'; file = 'emulator-windows_x64-16740729.zip'; size = 455344678 },
  @{ name = '안드로이드 14 이미지 (Google Play 포함)'; url = 'https://dl.google.com/android/repository/sys-img/google_apis_playstore/x86_64-34_r14.zip'; file = 'x86_64-34_r14.zip'; size = 1510752654 },
  @{ name = 'ADB 키보드 (한글 입력용)'; url = 'https://github.com/senzhk/ADBKeyBoard/raw/master/ADBKeyboard.apk'; file = 'ADBKeyboard.apk'; size = 0 }
)

function Get-File($it) {
  $dst = Join-Path $Dl $it.file
  if ((Test-Path $dst) -and ($it.size -eq 0 -or (Get-Item $dst).Length -eq $it.size)) { Say ('  이미 받음: ' + $it.name); return $dst }
  Say ('  받는 중: ' + $it.name + ' …')
  $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
  if (Test-Path $curl) {
    & $curl -L --fail --retry 3 -C - -o $dst $it.url
  } else {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $it.url -OutFile $dst -UseBasicParsing
  }
  if (-not (Test-Path $dst)) { Fail ('내려받지 못했어요: ' + $it.name) }
  if ($it.size -ne 0 -and (Get-Item $dst).Length -ne $it.size) { Fail ('파일 크기가 달라요(받다가 끊긴 것 같아요). setup.bat 을 다시 실행해 주세요: ' + $it.file) }
  return $dst
}

function Expand-To($zip, $dest) {
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
  if (Test-Path $tar) { & $tar -xf $zip -C $dest } else { Expand-Archive -Path $zip -DestinationPath $dest -Force }
}

Say '1/4 필요한 파일을 받아요.'
$got = @{}
foreach ($it in $items) { $got[$it.file] = Get-File $it }

Say '2/4 압축을 풀어요. (몇 분 걸려요)'
if (-not (Test-Path $Adb))      { Expand-To $got['platform-tools_r37.0.1-win.zip'] $Sdk }
if (-not (Test-Path $Emulator)) { Expand-To $got['emulator-windows_x64-16740729.zip'] $Sdk }
$imgDir = Join-Path $Sdk 'system-images\android-34\google_apis_playstore'
if (-not (Test-Path (Join-Path $imgDir 'x86_64\system.img'))) { Expand-To $got['x86_64-34_r14.zip'] $imgDir }

if (-not (Test-Path $Adb))      { Fail 'adb.exe 가 없어요. 압축 풀기가 실패했어요.' }
if (-not (Test-Path $Emulator)) { Fail 'emulator.exe 가 없어요. 압축 풀기가 실패했어요.' }
if (-not (Test-Path (Join-Path $imgDir 'x86_64\system.img'))) { Fail '안드로이드 이미지가 없어요. 압축 풀기가 실패했어요.' }

Say '3/4 가상 기기(gb)를 만들어요.'
$avdDir = Join-Path $AvdHome ($AvdName + '.avd')
New-Item -ItemType Directory -Force -Path $avdDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines((Join-Path $AvdHome ($AvdName + '.ini')), @(
  'avd.ini.encoding=UTF-8',
  ('path=' + $avdDir),
  ('path.rel=avd\' + $AvdName + '.avd'),
  'target=android-34'
), $utf8)
$cfg = Join-Path $avdDir 'config.ini'
if (-not (Test-Path $cfg)) {
  [System.IO.File]::WriteAllLines($cfg, @(
    'AvdId=gb',
    'avd.ini.displayname=gb',
    'abi.type=x86_64',
    'hw.cpu.arch=x86_64',
    'hw.cpu.ncore=4',
    'hw.ramSize=4096',
    'disk.dataPartition.size=16G',
    'hw.lcd.width=1080',
    'hw.lcd.height=2340',
    'hw.lcd.density=440',
    'hw.keyboard=yes',
    'hw.gpu.enabled=yes',
    'hw.gpu.mode=auto',
    'hw.mainKeys=no',
    'hw.camera.back=none',
    'hw.camera.front=none',
    'PlayStore.enabled=true',
    'tag.id=google_apis_playstore',
    'tag.display=Google Play',
    ('image.sysdir.1=' + $SysImgRel),
    'showDeviceFrame=no',
    'fastboot.forceColdBoot=yes'
  ), $utf8)
}

Say '4/4 가속(가상화)이 되는지 확인해요.'
$acc = (& $Emulator -accel-check 2>&1 | Out-String)
Say $acc
if ($acc -notmatch 'is installed and usable|accel:\s*0') {
  Warn '가속을 쓸 수 없다고 나와요. 이대로는 에뮬레이터가 켜지지 않거나 아주 느려요.'
  Warn 'README 의 "문제가 생겼을 때 > 가속" 을 따라 Windows 하이퍼바이저 플랫폼을 켠 뒤 다시 실행해 주세요.'
}

Say ''
Say '설치가 끝났어요. 이제 start.bat 을 실행해 주세요.'
