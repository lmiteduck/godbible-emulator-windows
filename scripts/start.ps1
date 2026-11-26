# 에뮬레이터를 켜고, 다 켜질 때까지 기다린 뒤 화면 기준(360x780)을 맞춰요.
. "$PSScriptRoot\common.ps1"
if (-not (Test-Installed)) { Fail '아직 설치가 안 됐어요. 먼저 setup.bat 을 실행해 주세요.' }

$serial = Get-Serial
if ($serial) {
  Say ('이미 켜져 있어요: ' + $serial)
} else {
  & $Adb kill-server 2>$null | Out-Null
  & $Adb start-server 2>$null | Out-Null
  Say '에뮬레이터를 켜고 있어요. 폰 모양 창이 뜰 때까지 1~3분 걸려요. (처음 켤 때는 더 걸려요)'
  $log = Join-Path $Root 'emulator.log'
  $err = Join-Path $Root 'emulator.err.log'
  Start-Process -FilePath $Emulator -ArgumentList @('-avd', $AvdName, '-no-metrics', '-no-snapshot-load', '-no-boot-anim') -RedirectStandardOutput $log -RedirectStandardError $err | Out-Null
  $t0 = Get-Date
  while (-not $serial) {
    Start-Sleep -Seconds 3
    $serial = Get-Serial
    if (((Get-Date) - $t0).TotalSeconds -gt 240) { Fail '에뮬레이터가 4분 안에 나타나지 않았어요. emulator.err.log 를 확인하거나 doctor.bat 결과를 담당자에게 보내 주세요.' }
  }
}

Say '안드로이드가 다 켜질 때까지 기다려요.'
$t0 = Get-Date
while ($true) {
  $b = Adb-Shell $serial @('getprop', 'sys.boot_completed')
  if ($b -eq '1') { break }
  if (((Get-Date) - $t0).TotalSeconds -gt 600) { Fail '10분이 지나도 다 켜지지 않았어요. 창을 닫고 start.bat 을 다시 실행해 주세요.' }
  Start-Sleep -Seconds 3
}
Start-Sleep -Seconds 3

# 화면 기준: 1080x2340 에 밀도 480 = 360x780dp. 맥에서 QA · 캡처하던 값과 같아요.
& $Adb -s $serial shell wm density 480 2>$null | Out-Null

# 한글 입력용 ADB 키보드 (없을 때만 깔아요. 기본 키보드는 그대로 둬요)
$has = Adb-Shell $serial @('pm', 'list', 'packages', 'com.android.adbkeyboard')
$apk = Join-Path $Dl 'ADBKeyboard.apk'
if (-not $has -and (Test-Path $apk)) {
  & $Adb -s $serial install -r $apk 2>$null | Out-Null
  & $Adb -s $serial shell ime enable $AdbImeId 2>$null | Out-Null
}

Say ''
Say ('준비됐어요. 기기: ' + $serial + ' / 화면: ' + (Adb-Shell $serial @('wm', 'size')) + ' / ' + (Adb-Shell $serial @('wm', 'density')))
Say '처음이라면: 에뮬 화면에서 Play 스토어에 QA용 구글 계정으로 로그인하고 갓바이블을 설치해 주세요. (QA 빌드 파일이 있으면 gb.bat install 파일경로)'
Say '명령 목록은 gb.bat help'
