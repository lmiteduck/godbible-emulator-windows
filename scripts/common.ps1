# 공통 설정. 다른 스크립트가 맨 위에서 불러 써요.
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Root     = Split-Path -Parent $PSScriptRoot
$Sdk      = Join-Path $Root 'sdk'
$AvdHome  = Join-Path $Root 'avd'
$EmuHome  = Join-Path $Root 'android_home'
$Dl       = Join-Path $Root 'dl'
$Out      = Join-Path $Root 'out'
$AvdName  = 'gb'
$Adb      = Join-Path $Sdk 'platform-tools\adb.exe'
$Emulator = Join-Path $Sdk 'emulator\emulator.exe'
$SysImgRel = 'system-images\android-34\google_apis_playstore\x86_64\'
$AdbImeId   = 'com.android.adbkeyboard/.AdbIME'
$LatinImeId = 'com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME'

# SDK · AVD · 에뮬 설정을 모두 이 폴더 안에 둬요. PC의 다른 안드로이드 설치와 섞이지 않아요.
$env:ANDROID_SDK_ROOT      = $Sdk
$env:ANDROID_HOME          = $Sdk
$env:ANDROID_AVD_HOME      = $AvdHome
$env:ANDROID_EMULATOR_HOME = $EmuHome

function Say([string]$msg)  { Write-Host $msg }
function Warn([string]$msg) { Write-Host ("[주의] " + $msg) -ForegroundColor Yellow }
function Fail([string]$msg) { Write-Host ("[멈춤] " + $msg) -ForegroundColor Red; exit 1 }

function Test-Installed {
  return (Test-Path $Adb) -and (Test-Path $Emulator) -and (Test-Path (Join-Path $Sdk ($SysImgRel + 'system.img'))) -and (Test-Path (Join-Path $AvdHome ($AvdName + '.ini')))
}

# 켜져 있는 에뮬 이름(emulator-5554 등)을 찾아요. 없으면 빈 글자.
function Get-Serial {
  if (-not (Test-Path $Adb)) { return '' }
  $lines = & $Adb devices 2>$null
  foreach ($l in $lines) { if ($l -match '^(emulator-\d+)\s+device') { return $Matches[1] } }
  return ''
}

function Require-Device {
  $s = Get-Serial
  if (-not $s) { Fail '켜져 있는 에뮬레이터가 없어요. 먼저 start.bat 을 실행해 주세요.' }
  return $s
}

function Adb-Shell([string]$serial, [string[]]$cmd) {
  $o = & $Adb -s $serial shell @cmd 2>$null
  if ($null -eq $o) { return '' }
  return (($o | Out-String).Trim())
}
