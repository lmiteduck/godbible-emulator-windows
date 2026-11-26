# QA 때 쓰는 명령 모음. 쓰는 법: gb.bat <명령> [값]
param(
  [Parameter(Position = 0)][string]$Cmd = 'help',
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest
)
. "$PSScriptRoot\common.ps1"
if ($null -eq $Rest) { $Rest = @() }

function Stamp { return (Get-Date -Format 'yyyyMMdd-HHmmss') }
function Day   { return (Get-Date -Format 'yyyyMMdd') }
function Safe-Name([string]$n) { if (-not $n) { return (Stamp) }; return ($n -replace '[\\/:*?"<>|\s]+', '-') }

function Get-Ui([string]$serial) {
  & $Adb -s $serial shell uiautomator dump /sdcard/gb_ui.xml 2>$null | Out-Null
  $tmp = Join-Path $env:TEMP 'gb_ui.xml'
  & $Adb -s $serial pull /sdcard/gb_ui.xml $tmp 2>$null | Out-Null
  if (-not (Test-Path $tmp)) { return @() }
  try { [xml]$x = Get-Content -Raw -Encoding UTF8 $tmp } catch { return @() }
  $res = @()
  foreach ($n in $x.SelectNodes('//node')) {
    $t = $n.GetAttribute('text'); if (-not $t) { $t = $n.GetAttribute('content-desc') }
    if ($n.GetAttribute('bounds') -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
      $x1 = [int]$Matches[1]; $y1 = [int]$Matches[2]; $x2 = [int]$Matches[3]; $y2 = [int]$Matches[4]
      $res += [pscustomobject]@{ text = ($t -replace "`n", ' / '); click = ($n.GetAttribute('clickable') -eq 'true'); cx = [int](($x1 + $x2) / 2); cy = [int](($y1 + $y2) / 2); w = ($x2 - $x1); h = ($y2 - $y1) }
    }
  }
  return $res
}

function Find-App([string]$serial) {
  $p = Adb-Shell $serial @('pm', 'list', 'packages')
  $hit = ($p -split "`n") | Where-Object { $_ -match 'godbible' } | Select-Object -First 1
  if ($hit) { return ($hit -replace 'package:', '').Trim() }
  return ''
}

switch ($Cmd) {

  'help' {
    Say '갓바이블 QA 에뮬레이터 명령'
    Say '  gb doctor                  설치 · 가속 · 기기 · 앱 버전 상태를 한 번에 보여 줘요 (문제가 있으면 이 결과를 보내 주세요)'
    Say '  gb app                     깔려 있는 갓바이블 앱 이름과 버전'
    Say '  gb install <apk 경로>      QA 빌드(apk) 깔기'
    Say '  gb shot <이름>             화면 찍기 → out\shots\날짜\이름.png (360 폭 사본도 같이)'
    Say '  gb rec <이름> [초]         화면 녹화 (기본 20초) → out\rec\'
    Say '  gb logs <이름>             지금까지의 로그 저장 → out\logs\'
    Say '  gb texts                   화면에 보이는 글과 누를 수 있는 곳 목록'
    Say '  gb tap "<글>" [번째]       그 글이 있는 곳 누르기 (정규식, 0부터)'
    Say '  gb tapxy <x> <y>           좌표 누르기 (px, 화면은 1080x2340)'
    Say '  gb swipe up|down           화면 넘기기'
    Say '  gb back                    뒤로 (홈 · MY 같은 첫 화면에서는 누르지 마세요. 앱이 꺼져요)'
    Say '  gb ime on|off              한글 입력용 키보드로 바꾸기 / 원래 키보드로 되돌리기'
    Say '  gb type "<글>"             글 넣기 (ime on → 칸 누르기 → type → ime off 순서)'
    Say '  gb density [480|reset]     화면 기준 맞추기 (기본 480 = 360x780)'
    Say '  gb stop                    에뮬레이터 끄기'
  }

  'doctor' {
    Say ('설치 폴더: ' + $Root)
    Say ('윈도우: ' + [Environment]::OSVersion.VersionString + ' / ' + $env:PROCESSOR_ARCHITECTURE)
    Say ('설치됨: ' + (Test-Installed))
    if (Test-Path $Emulator) { Say '--- 가속 확인'; Say ((& $Emulator -accel-check 2>&1 | Out-String).Trim()) }
    if (Test-Path $Adb) { Say '--- 기기'; Say ((& $Adb devices 2>&1 | Out-String).Trim()) }
    $s = Get-Serial
    if ($s) {
      Say ('화면: ' + (Adb-Shell $s @('wm', 'size')) + ' / ' + (Adb-Shell $s @('wm', 'density')))
      Say ('안드로이드: ' + (Adb-Shell $s @('getprop', 'ro.build.version.release')) + ' (API ' + (Adb-Shell $s @('getprop', 'ro.build.version.sdk')) + ')')
      $pkg = Find-App $s
      if ($pkg) {
        $ver = @((Adb-Shell $s @('dumpsys', 'package', $pkg)) -split "`n" | Where-Object { $_ -match 'versionName|versionCode' } | Select-Object -First 2 | ForEach-Object { $_.Trim() })
        Say ('앱: ' + $pkg + ' / ' + ($ver -join ' / '))
      }
      else { Say '앱: 갓바이블이 아직 안 깔려 있어요.' }
    }
    $errLog = Join-Path $Root 'emulator.err.log'
    if (Test-Path $errLog) { Say '--- emulator.err.log 마지막 15줄'; Get-Content $errLog -Tail 15 | ForEach-Object { Say $_ } }
  }

  'app' {
    $s = Require-Device; $pkg = Find-App $s
    if (-not $pkg) { Say '갓바이블이 아직 안 깔려 있어요. Play 스토어에서 깔거나 gb install <apk> 를 써 주세요.'; break }
    Say $pkg
    (Adb-Shell $s @('dumpsys', 'package', $pkg)) -split "`n" | Where-Object { $_ -match 'versionName|versionCode|firstInstallTime|lastUpdateTime' } | ForEach-Object { Say ('  ' + $_.Trim()) }
  }

  'install' {
    $s = Require-Device
    if ($Rest.Count -lt 1 -or -not (Test-Path $Rest[0])) { Fail 'apk 파일 경로를 적어 주세요. 예: gb install C:\Downloads\godbible-qa.apk' }
    & $Adb -s $s install -r $Rest[0]
  }

  'shot' {
    $s = Require-Device
    $dir = Join-Path $Out ('shots\' + (Day)); New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $name = Safe-Name ($Rest -join ' ')
    $png = Join-Path $dir ($name + '.png')
    & $Adb -s $s shell screencap -p /sdcard/gb_shot.png 2>$null | Out-Null
    & $Adb -s $s pull /sdcard/gb_shot.png $png 2>$null | Out-Null
    if (-not (Test-Path $png)) { Fail '화면을 찍지 못했어요.' }
    try {
      Add-Type -AssemblyName System.Drawing
      $img = [System.Drawing.Image]::FromFile($png)
      $h = [int]($img.Height * 360 / $img.Width)
      $bmp = New-Object System.Drawing.Bitmap 360, $h
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.DrawImage($img, 0, 0, 360, $h)
      $bmp.Save((Join-Path $dir ($name + '_360.png')), [System.Drawing.Imaging.ImageFormat]::Png)
      $g.Dispose(); $bmp.Dispose(); $img.Dispose()
    } catch { Warn '360 폭 사본은 만들지 못했어요. 원본은 저장됐어요.' }
    Say $png
  }

  'rec' {
    $s = Require-Device
    $dir = Join-Path $Out 'rec'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $name = Safe-Name $Rest[0]; $sec = 20
    if ($Rest.Count -ge 2) { $sec = [int]$Rest[1] }
    Say ($sec.ToString() + '초 동안 녹화해요. 에뮬 화면에서 재현해 주세요.')
    & $Adb -s $s shell screenrecord --time-limit $sec /sdcard/gb_rec.mp4 2>$null | Out-Null
    $mp4 = Join-Path $dir ($name + '.mp4')
    & $Adb -s $s pull /sdcard/gb_rec.mp4 $mp4 2>$null | Out-Null
    Say $mp4
  }

  'logs' {
    $s = Require-Device
    $dir = Join-Path $Out 'logs'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $f = Join-Path $dir ((Safe-Name ($Rest -join ' ')) + '-' + (Stamp) + '.txt')
    & $Adb -s $s shell logcat -d -v time -f /sdcard/gb_log.txt 2>$null | Out-Null
    & $Adb -s $s pull /sdcard/gb_log.txt $f 2>$null | Out-Null
    Say $f
    Say '(로그에는 계정 정보가 섞여 있을 수 있어요. 밖으로 보낼 때는 필요한 부분만 잘라 보내 주세요.)'
  }

  'texts' {
    $s = Require-Device
    foreach ($n in (Get-Ui $s)) { if ($n.text) { Say (('{0,5},{1,5}  {2}  {3}' -f $n.cx, $n.cy, $(if ($n.click) { '[누름]' } else { '      ' }), $n.text)) } }
  }

  'tap' {
    $s = Require-Device
    if ($Rest.Count -lt 1) { Fail '누를 글을 적어 주세요. 예: gb tap "내 계정"' }
    $idx = 0; if ($Rest.Count -ge 2) { $idx = [int]$Rest[1] }
    $hit = @(Get-Ui $s | Where-Object { $_.text -match $Rest[0] })
    if ($hit.Count -le $idx) { Say ('못 찾았어요: ' + $Rest[0] + ' (찾은 수 ' + $hit.Count + ')'); exit 2 }
    & $Adb -s $s shell input tap $hit[$idx].cx $hit[$idx].cy
    Say ('눌렀어요: ' + $hit[$idx].text + ' @ ' + $hit[$idx].cx + ',' + $hit[$idx].cy)
  }

  'tapxy' { $s = Require-Device; if ($Rest.Count -lt 2) { Fail '좌표 두 개를 적어 주세요. 예: gb tapxy 540 1200' }; & $Adb -s $s shell input tap $Rest[0] $Rest[1] }
  'back'  { $s = Require-Device; & $Adb -s $s shell input keyevent 4 }

  'swipe' {
    $s = Require-Device
    if ($Rest[0] -eq 'down') { & $Adb -s $s shell input swipe 540 700 540 1700 400 }
    else { & $Adb -s $s shell input swipe 540 1700 540 700 400 }
  }

  'ime' {
    $s = Require-Device
    if ($Rest[0] -eq 'on') {
      & $Adb -s $s shell ime enable $AdbImeId 2>$null | Out-Null
      & $Adb -s $s shell ime set $AdbImeId 2>$null | Out-Null
      Say '한글 입력용 키보드로 바꿨어요. 이제 입력할 칸을 누른 뒤 gb type "글" 을 실행해 주세요.'
    } else {
      & $Adb -s $s shell ime set $LatinImeId 2>$null | Out-Null
      Say '원래 키보드로 되돌렸어요. (화면을 찍기 전에 꼭 되돌려 주세요)'
    }
  }

  'type' {
    $s = Require-Device
    $text = ($Rest -join ' ')
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($text))
    & $Adb -s $s shell am broadcast -a ADB_INPUT_B64 --es msg $b64 2>$null | Out-Null
    Say ('넣었어요: ' + $text)
  }

  'density' {
    $s = Require-Device
    if ($Rest.Count -ge 1 -and $Rest[0] -eq 'reset') { & $Adb -s $s shell wm density reset } else { $d = '480'; if ($Rest.Count -ge 1) { $d = $Rest[0] }; & $Adb -s $s shell wm density $d }
    Say (Adb-Shell $s @('wm', 'density'))
  }

  'stop' {
    $s = Get-Serial
    if ($s) { & $Adb -s $s emu kill 2>$null | Out-Null; Say '에뮬레이터를 껐어요.' } else { Say '켜져 있는 에뮬레이터가 없어요.' }
  }

  default { Say ('모르는 명령이에요: ' + $Cmd + '  →  gb help') }
}
