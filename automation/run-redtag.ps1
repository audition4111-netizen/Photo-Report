# 조작대상 찾기 — 세 팀 무인 실행기
#
# 하는 일: queue.json 에서 아직 안 한 일을 하나 꺼내 claude 에게 시키고,
#          끝나면 결과를 적고 다음 일로 넘어간다. 큐가 비면 쉬었다 다시 본다.
#
# 토큰이 떨어지면: 한도 안내에 적힌 **리셋 시각까지 자고** 같은 일을 다시 한다.
#                 사람이 지켜보지 않아도 알아서 이어 간다.
#
# 쓰는 법:
#   powershell -ExecutionPolicy Bypass -File automation\run-redtag.ps1
#   (install.ps1 을 돌리면 로그인할 때 저절로 뜬다)
#
# 멈추는 법: automation\STOP 이라는 빈 파일을 만들면 그 일만 끝내고 선다.

[CmdletBinding()]
param(
  [int]$IdleMinutes = 10,      # 큐가 비었을 때 다시 볼 때까지 쉬는 시간
  [int]$MaxRetries  = 2,       # 한도 말고 다른 오류로 실패했을 때 다시 해 볼 횟수
  [switch]$Once                # 한 번만 돌고 끝낸다(시험용)
)

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $PSScriptRoot      # 저장소 뿌리
$Here    = $PSScriptRoot
$Queue   = Join-Path $Here 'queue.json'
$LogDir  = Join-Path $Here 'logs'
$Lock    = Join-Path $Here '.running'
$StopF   = Join-Path $Here 'STOP'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory $LogDir | Out-Null }

function Write-Log {
  param([string]$Msg, [string]$Level = 'INFO')
  $line = ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Msg)
  Write-Host $line
  $daily = Join-Path $LogDir ('runner-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
  Add-Content -Path $daily -Value $line -Encoding utf8
}

# ── 두 번 뜨지 않게 ────────────────────────────────────────────────────────
if (Test-Path $Lock) {
  $pidTxt = Get-Content $Lock -Raw -ErrorAction SilentlyContinue
  $old = 0; [int]::TryParse($pidTxt.Trim(), [ref]$old) | Out-Null
  if ($old -gt 0 -and (Get-Process -Id $old -ErrorAction SilentlyContinue)) {
    Write-Log "이미 돌고 있습니다(PID $old). 그냥 나갑니다." 'WARN'
    exit 0
  }
  Write-Log "지난번 잠금이 남아 있어 지웁니다(PID $old 는 없음)." 'WARN'
  Remove-Item $Lock -Force
}
Set-Content -Path $Lock -Value $PID -Encoding utf8

# ── 큐 읽고 쓰기 ──────────────────────────────────────────────────────────
function Read-Queue {
  if (-not (Test-Path $Queue)) { return @() }
  $raw = Get-Content $Queue -Raw -Encoding utf8
  if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
  $v = $raw | ConvertFrom-Json
  if ($null -eq $v) { return @() }
  # 하나짜리도 배열로
  return @($v)
}

function Save-Queue {
  param($Items)
  $json = ($Items | ConvertTo-Json -Depth 12)
  Set-Content -Path $Queue -Value $json -Encoding utf8
}

# ── 한도에 걸렸는지, 걸렸으면 언제 풀리는지 ────────────────────────────────
function Get-ResetTime {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

  # "Your limit will reset at 3pm (Asia/Seoul)" / "resets at 15:00" 같은 꼴
  $m = [regex]::Match($Text, 'reset[s]?\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?', 'IgnoreCase')
  if ($m.Success) {
    $h = [int]$m.Groups[1].Value
    $mi = 0; if ($m.Groups[2].Success) { $mi = [int]$m.Groups[2].Value }
    $ap = $m.Groups[3].Value.ToLower()
    if ($ap -eq 'pm' -and $h -lt 12) { $h += 12 }
    if ($ap -eq 'am' -and $h -eq 12) { $h = 0 }
    $t = (Get-Date).Date.AddHours($h).AddMinutes($mi)
    if ($t -le (Get-Date)) { $t = $t.AddDays(1) }   # 이미 지났으면 내일
    return $t
  }

  # 유닉스 초 꼴 ("resets at 1764000000")
  $m2 = [regex]::Match($Text, '\b(1[0-9]{9})\b')
  if ($m2.Success) {
    return [DateTimeOffset]::FromUnixTimeSeconds([long]$m2.Groups[1].Value).LocalDateTime
  }
  return $null
}

function Test-UsageLimit {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return ($Text -match 'usage limit|rate.?limit|limit reached|too many requests|429|quota')
}

# ── 일 하나 시키기 ────────────────────────────────────────────────────────
function Invoke-Task {
  param([string]$Prompt, [string]$Model)

  $cliArgs = @(
    '-p', $Prompt,
    '--output-format', 'json',
    '--permission-mode', 'bypassPermissions',
    '--add-dir', 'C:\업무자료',
    '--add-dir', 'C:\Users\User\OneDrive\바탕 화면\GitHub\red-tag-manager',
    # 돌이킬 수 없는 것은 막아 둔다 — 무인으로 도는 동안 사람이 못 말린다
    '--disallowed-tools',
      'Bash(git push:*)','Bash(git reset --hard:*)','Bash(rm -rf:*)',
      'Bash(rmdir /s:*)','Bash(del /f:*)','Bash(format:*)'
  )
  if ($Model) { $cliArgs += @('--model', $Model) }

  Push-Location $Root
  try {
    $out = & claude @cliArgs 2>&1 | Out-String
  } finally {
    Pop-Location
  }
  return $out
}

# ── 본 흐름 ───────────────────────────────────────────────────────────────
Write-Log "실행기 시작 (저장소: $Root)"

try {
  while ($true) {
    if (Test-Path $StopF) {
      Write-Log 'STOP 파일이 있어 멈춥니다.' 'WARN'
      break
    }

    $items = Read-Queue
    $task  = $items | Where-Object { $_.status -eq 'pending' } | Select-Object -First 1

    if (-not $task) {
      if ($Once) { Write-Log '할 일이 없습니다. (-Once 라 끝냅니다)'; break }
      Write-Log "할 일이 없습니다. $IdleMinutes 분 뒤에 다시 봅니다."
      Start-Sleep -Seconds ($IdleMinutes * 60)
      continue
    }

    Write-Log ("일 시작 [{0}] {1}" -f $task.id, $task.title)
    $task.status     = 'running'
    $task.started_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Save-Queue $items

    $attempt = 0
    $done    = $false

    while (-not $done) {
      $attempt++
      $raw = Invoke-Task -Prompt $task.prompt -Model $task.model

      # 한도에 걸렸나 — 걸렸으면 리셋까지 자고 같은 일을 다시 한다
      if (Test-UsageLimit $raw) {
        $reset = Get-ResetTime $raw
        if (-not $reset) { $reset = (Get-Date).AddMinutes(45) }   # 못 읽으면 넉넉히
        $wait = [int]([Math]::Max(60, ($reset - (Get-Date)).TotalSeconds + 120))  # 2분 여유
        Write-Log ("토큰 한도. {0} 까지 {1}분 자고 같은 일을 다시 합니다." -f
                   $reset.ToString('MM-dd HH:mm'), [int]($wait/60)) 'WARN'
        $task.status = 'waiting_limit'
        $task.resume_at = $reset.ToString('yyyy-MM-dd HH:mm:ss')
        Save-Queue $items
        Start-Sleep -Seconds $wait
        $task.status = 'running'
        Save-Queue $items
        $attempt--        # 한도는 실패로 세지 않는다
        continue
      }

      # 결과 갈무리
      $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
      $outF  = Join-Path $LogDir ("{0}-{1}.json" -f $task.id, $stamp)
      Set-Content -Path $outF -Value $raw -Encoding utf8

      $ok = $false; $resultText = ''
      try {
        $j = $raw | ConvertFrom-Json
        $ok = (-not $j.is_error) -and ($j.subtype -eq 'success')
        $resultText = $j.result
      } catch {
        # JSON 이 아니면 (오류 메시지 등) 실패로 본다
        $resultText = $raw.Substring(0, [Math]::Min(2000, $raw.Length))
      }

      if ($ok) {
        $task.status      = 'done'
        $task.finished_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        $task.output_file = $outF
        # 보고 앞머리만 큐에 남겨 둔다 — 자세한 건 output_file 에
        $task | Add-Member -NotePropertyName summary -NotePropertyValue (
          $resultText.Substring(0, [Math]::Min(1200, $resultText.Length))) -Force
        Save-Queue $items
        Write-Log ("일 끝 [{0}] → {1}" -f $task.id, (Split-Path $outF -Leaf))
        $done = $true
      }
      elseif ($attempt -gt $MaxRetries) {
        $task.status      = 'failed'
        $task.finished_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        $task.output_file = $outF
        $task | Add-Member -NotePropertyName error -NotePropertyValue (
          $resultText.Substring(0, [Math]::Min(1200, $resultText.Length))) -Force
        Save-Queue $items
        Write-Log ("일 실패 [{0}] {1}회 해 봤습니다. 로그: {2}" -f
                   $task.id, $attempt, (Split-Path $outF -Leaf)) 'ERROR'
        $done = $true
      }
      else {
        Write-Log ("일 오류 [{0}] {1}회째. 1분 뒤 다시 합니다." -f $task.id, $attempt) 'WARN'
        Start-Sleep -Seconds 60
      }
    }

    if ($Once) { break }
  }
}
finally {
  Remove-Item $Lock -Force -ErrorAction SilentlyContinue
  Write-Log '실행기 종료'
}
