#Requires -Version 7.0
<#
  dialog-verify.ps1 —— 对话清理后的机械校验（D83）

  硬失败（exit 1）：引号不配对 / 出现「」/ 连续两个空行 / 相邻重复段
  警告：汉字变化超过 5% / 一段换人 / 空转句式超配额

  用法：
    pwsh -File tools\dialog-verify.ps1                # 全书
    pwsh -File tools\dialog-verify.ps1 -Chapter 13
#>
param(
  [string]$Chapter = 'all',
  [string]$Baseline = 'tools\out\baseline.csv'
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$QO = [string][char]0x201C
$QC = [string][char]0x201D
$LB = [string][char]0x300C
$RB = [string][char]0x300D

function Get-Paras {
  param([string]$Path)
  $lines = Get-Content -LiteralPath $Path -Encoding UTF8
  $out = New-Object System.Collections.Generic.List[object]
  $n = 0
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $t = $lines[$i].Trim()
    if ($t.Length -gt 0) { $n++; $out.Add([pscustomobject]@{ Line = $i + 1; Ord = $n; Text = $t }) }
  }
  return ,$out
}

function Get-Stats {
  param([string]$Path)
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $lines = Get-Content -LiteralPath $Path -Encoding UTF8
  $paras = Get-Paras -Path $Path
  $han = ([regex]::Matches($raw, '[\u4e00-\u9fff]')).Count
  $blankRun = 0; $maxBlank = 0; $badGap = 0
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim().Length -eq 0) { $blankRun++; if ($blankRun -gt $maxBlank) { $maxBlank = $blankRun } }
    else {
      if ($blankRun -eq 2 -and $lines[$i].Trim() -ne '***' -and $lines[$i].Trim() -ne '---') { $badGap++ }
      $blankRun = 0
    }
  }
  $dupes = 0
  for ($i = 1; $i -lt $paras.Count; $i++) { if ($paras[$i].Text -eq $paras[$i - 1].Text) { $dupes++ } }
  $huan = 0
  foreach ($p in $paras) {
    if (([regex]::Matches($p.Text, $QO)).Count -lt 2) { continue }
    $spk = @()
    foreach ($m in [regex]::Matches($p.Text, $QC + '([^' + $QO + $QC + ']{0,4}?)(说|问|道|答|喊|叫|嚷|叹)')) {
      $sn = ($m.Groups[1].Value -replace '^[，。！？、；：\s]+', '' -replace '[，。！？、；：\s]+$', '')
      if ($sn -notmatch '[了的得地]') { $spk += $sn }
    }
    $u = @($spk | Where-Object { $_.Length -gt 0 } | Select-Object -Unique)
    if ($u.Count -ge 2) { $huan++ }
  }
  [pscustomobject]@{
    汉字 = $han
    段 = $paras.Count
    字每段 = if ($paras.Count) { [math]::Round($han / $paras.Count, 1) } else { 0 }
    对话段 = @($paras | Where-Object { $_.Text.StartsWith($QO) }).Count
    含3引号 = @($paras | Where-Object { ([regex]::Matches($_.Text, $QO)).Count -ge 3 }).Count
    短看着 = @($paras | Where-Object { $_.Text -match '看着' -and $_.Text.Length -le 30 -and -not $_.Text.Contains($QO) }).Count
    没说话 = @($paras | Where-Object { $_.Text -match '没有说话|没说话|没有答话|没有回答' -and $_.Text.Length -le 30 -and -not $_.Text.Contains($QO) }).Count
    沉默 = @($paras | Where-Object { $_.Text -match '沉默' -and $_.Text.Length -le 25 -and -not $_.Text.Contains($QO) }).Count
    极短对话 = @($paras | Where-Object { $_.Text.StartsWith($QO) -and $_.Text.Length -le 10 }).Count
    换人段 = $huan
    开引号 = ([regex]::Matches($raw, $QO)).Count
    闭引号 = ([regex]::Matches($raw, $QC)).Count
    左角 = ([regex]::Matches($raw, $LB)).Count
    右角 = ([regex]::Matches($raw, $RB)).Count
    最大连续空行 = $maxBlank
    异常双空行 = $badGap
    相邻重复 = $dupes
    首行 = if ($lines.Count) { $lines[0] } else { '' }
  }
}

$baseMap = @{}
$basePath = Join-Path $Root $Baseline
if (Test-Path -LiteralPath $basePath) {
  Import-Csv -LiteralPath $basePath | ForEach-Object { $baseMap[$_.章] = $_ }
} else {
  Write-Warning "没有基线：$basePath（先跑 dialog-audit.ps1 -WriteBaseline）"
}

$all = 1..15 | ForEach-Object { if ($_ -lt 10) { "0$_" } else { "$_" } }
$chs = if ($Chapter -eq 'all') { $all } else { @((($Chapter -replace '[^0-9]', '')).PadLeft(2, '0')) }

$rows = New-Object System.Collections.Generic.List[object]
$hardFail = $false

foreach ($ch in $chs) {
  $path = Join-Path $Root "正文\ch$ch.md"
  if (-not (Test-Path -LiteralPath $path)) { Write-Warning "缺文件：$path"; continue }
  $s = Get-Stats -Path $path

  $fails = New-Object System.Collections.Generic.List[string]
  $warns = New-Object System.Collections.Generic.List[string]

  if ($s.开引号 -ne $s.闭引号) { $fails.Add("引号不配对：$($s.开引号) / $($s.闭引号)") }
  if (($s.左角 + $s.右角) -gt 0) { $fails.Add("出现「」：$($s.左角 + $s.右角)") }
  if ($s.最大连续空行 -gt 2) { $fails.Add("连续空行 $($s.最大连续空行) 行") }
  if ($s.异常双空行 -gt 0) { $warns.Add("双空行后不是场景分隔符：$($s.异常双空行) 处") }
  if ($s.相邻重复 -gt 0) { $fails.Add("相邻重复段 $($s.相邻重复) 处") }
  if (-not $s.首行.StartsWith('# ')) { $warns.Add("首行不是章节标题") }

  $b = $baseMap["ch$ch"]
  $hanDelta = ''
  if ($b) {
    $bh = [int]$b.汉字
    $pct = if ($bh) { [math]::Round(($s.汉字 - $bh) / $bh * 100, 1) } else { 0 }
    $hanDelta = "$bh → $($s.汉字)（$pct%）"
    if ($pct -lt -5) { $warns.Add("汉字降幅 $pct% 超过 −5%") }
  }
  if ($s.短看着 -gt 2) { $warns.Add("短看着段 $($s.短看着)（配额 ≤ 2）") }
  if ($s.没说话 -gt 2) { $warns.Add("没说话段 $($s.没说话)（配额 ≤ 2）") }
  if ($s.沉默 -gt 2) { $warns.Add("沉默独立段 $($s.沉默)（配额 ≤ 2）") }
  if ($s.换人段 -gt 0) { $warns.Add("一段换人 $($s.换人段) 处（目标 0）") }

  if ($fails.Count -gt 0) { $hardFail = $true }

  $rows.Add([pscustomobject]@{
    章 = "ch$ch"; 汉字 = $s.汉字; 变化 = $hanDelta; 段 = $s.段; 字每段 = $s.字每段
    含3引号 = $s.含3引号; 短看着 = $s.短看着; 没说话 = $s.没说话; 换人 = $s.换人段
    结果 = if ($fails.Count) { 'FAIL' } elseif ($warns.Count) { 'WARN' } else { 'OK' }
    问题 = (@($fails) + @($warns)) -join '；'
  })
}

$rows | Format-Table -AutoSize -Wrap | Out-String -Width 200
if ($hardFail) { exit 1 }
