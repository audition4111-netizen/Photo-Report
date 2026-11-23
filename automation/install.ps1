# 무인 실행기를 Windows 작업 스케줄러에 등록한다.
#
#   powershell -ExecutionPolicy Bypass -File automation\install.ps1
#   powershell -ExecutionPolicy Bypass -File automation\install.ps1 -Remove   (해제)
#
# 등록하면: 로그인할 때 저절로 뜨고, 혹시 꺼져도 5분마다 살아 있는지 보고 다시 띄운다.
# 컴퓨터를 켜 두기만 하면 큐에 쌓인 일을 알아서 해 나간다.

param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$Here   = $PSScriptRoot
$Runner = Join-Path $Here 'run-redtag.ps1'
$Name   = 'RedTag-팀-무인실행'
$Keep   = 'RedTag-팀-살아있나'

if ($Remove) {
  foreach ($n in @($Name, $Keep)) {
    if (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue) {
      Unregister-ScheduledTask -TaskName $n -Confirm:$false
      Write-Host "지웠습니다: $n"
    }
  }
  Write-Host '해제 끝. (돌고 있던 실행기는 창을 닫거나 automation\STOP 파일을 만들면 섭니다)'
  exit 0
}

if (-not (Test-Path $Runner)) { throw "실행기를 못 찾았습니다: $Runner" }
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  throw 'claude CLI 가 PATH 에 없습니다. 먼저 Claude Code 를 설치하세요.'
}

$ps  = (Get-Command powershell).Source
$arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $Runner

# ① 로그인할 때 뜬다
$act1 = New-ScheduledTaskAction -Execute $ps -Argument $arg -WorkingDirectory $Here
$trg1 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
# 배터리로 돌아도 멈추지 않게, 시간 제한 없이
$set1 = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
          -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) `
          -MultipleInstances IgnoreNew -StartWhenAvailable
Register-ScheduledTask -TaskName $Name -Action $act1 -Trigger $trg1 -Settings $set1 `
  -Description '조작대상 찾기 — 검사·검증·만들기 팀을 큐에 따라 무인으로 돌린다. 토큰 한도에 걸리면 리셋까지 기다렸다 이어 간다.' `
  -Force | Out-Null
Write-Host "등록: $Name  (로그인할 때 뜸)"

# ② 5분마다 살아 있나 보고, 꺼져 있으면 다시 띄운다
#    실행기 안에 잠금(.running)이 있어 두 번 뜨지는 않는다.
$act2 = New-ScheduledTaskAction -Execute $ps -Argument $arg -WorkingDirectory $Here
$trg2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
          -RepetitionInterval (New-TimeSpan -Minutes 5)
$set2 = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
          -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
Register-ScheduledTask -TaskName $Keep -Action $act2 -Trigger $trg2 -Settings $set2 `
  -Description '실행기가 꺼져 있으면 다시 띄운다(이미 돌고 있으면 그냥 나간다).' `
  -Force | Out-Null
Write-Host "등록: $Keep  (5분마다 확인)"

Write-Host ''
Write-Host '끝났습니다. 지금 바로 한 번 돌려 보려면:'
Write-Host ('   Start-ScheduledTask -TaskName "{0}"' -f $Name)
Write-Host ''
Write-Host '멈추려면 automation\STOP 이라는 빈 파일을 만드세요(그 일만 끝내고 섭니다).'
Write-Host '기록은 automation\logs\ 에 날짜별로 쌓입니다.'
