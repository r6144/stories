#Requires -Version 7.0
<#
  dialog-audit.ps1 —— 对话清理审计（D83）

  只读正文；除 tools\out\ 下的报告外不改任何文件。
  行号 = 正文文件里的真实行号（可直接当作 read 工具的 offset 用）。

  用法：
    pwsh -File tools\dialog-audit.ps1                  # 全书：打印汇总表，写 tools\out\chXX.audit.md
    pwsh -File tools\dialog-audit.ps1 -Chapter 13      # 只审一章（也接受 ch13 / 13）
    pwsh -File tools\dialog-audit.ps1 -WriteBaseline   # 重建 tools\out\baseline.csv

  报告里的类型：
    A1 独立看着段        看着 ta 单独成段（配额每章 ≤ 2）
    A2 没有说话/沉默段   没有说话、沉默一会儿单独成段（配额每章 ≤ 2）
    B1 极短对话段        引号内 ≤ 6 字，容易是空转应答
    B2 短问短答对        相邻两段都是对话且都很短，先看是不是一问一答的空转
    C1 一段换人          同段出现两个以上说话人 → 必须分段（D83 硬规则）
    C2 同人停顿续话      同段 ≥ 3 个引号但只有一个人在说；只提示，不当指标
    D1 相邻重复段        连续两段完全相同
#>
param(
  [string]$Chapter = 'all',
  [string]$OutDir = 'tools\out',
  [switch]$WriteBaseline
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$OutPath = Join-Path $Root $OutDir
if (-not (Test-Path -LiteralPath $OutPath)) { New-Item -ItemType Directory -Path $OutPath | Out-Null }

$QO = [string][char]0x201C   # 左引号
$Qc = [string][char]0x201D   # 右引号
$LB = [string][char]0x300C   # 「
$RB = [string][char]0x300D   # 」

# 常见人名：只用于“一段多回合”时估说话人数，不做别的判断
$Names = @(
  '林晚','妮露','纳西妲','芙宁娜','派蒙','荧','林尼','琳妮特','阿蕾奇诺','公子','若娜瓦',
  '婕德','拉娜','卡利贝尔','素达蓓','兰拉娜','兰罗摩','祖尔宛','斯露莎','米希尔','拉沙鲁',
  '帕丽莎','芭别尔','玛海菈','迪娜泽黛','艾尔海森','迪希雅','拉赫曼','哲伯莱勒','优菲','欣迪',
  '哈桑','那先朱那','塔德菈','利露帕尔','凯瑟琳','娜维娅','克洛琳德','莱欧斯利','那维莱特',
  '芙卡洛斯','厄歌莉娅','周慧','林志远','周姨','李姐','小陈','老陆头','浮锦','嘉明','闲云',
  '钟离','温迪','八重神子','提纳里','柯莱','坎蒂丝','赛诺','托马','宵宫','胡桃','申鹤','甘雨',
  '珐露珊','莱依拉','多莉','妮露母','老师','校长','船长','老板娘','主持人','摊主','瓦蕾莎',
  '基尼奇','茜特菈莉','玛拉妮','卡齐娜','阿托莎','欧洛伦','伊安珊','恰斯卡','希诺宁',
  '艾梅莉埃','克雷薇','佩露薇利','库嘉维娜','泽维尔','埃洛伊','妮可','罗莎琳','菲米尼'
)

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

function Get-Metrics {
  param([string]$Path, $Paras)
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $han = ([regex]::Matches($raw, '[\u4e00-\u9fff]')).Count
  $dial = @($Paras | Where-Object { $_.Text.StartsWith($QO) })
  $q2 = @($Paras | Where-Object { ([regex]::Matches($_.Text, $QO)).Count -eq 2 })
  $q3 = @($Paras | Where-Object { ([regex]::Matches($_.Text, $QO)).Count -ge 3 })
  $kan = @($Paras | Where-Object { $_.Text -match '看着' -and $_.Text.Length -le 30 -and -not $_.Text.Contains($QO) })
  $nosay = @($Paras | Where-Object { $_.Text -match '没有说话|没说话|没有答话|没有回答' -and $_.Text.Length -le 30 -and -not $_.Text.Contains($QO) })
  $sil = @($Paras | Where-Object { $_.Text -match '沉默' -and $_.Text.Length -le 25 -and -not $_.Text.Contains($QO) })
  $ack = @($dial | Where-Object { $_.Text.Length -le 10 })
  [pscustomobject]@{
    汉字 = $han; 段 = $Paras.Count; 字每段 = if ($Paras.Count) { [math]::Round($han / $Paras.Count, 1) } else { 0 }
    对话段 = $dial.Count; 含2引号 = $q2.Count; 含3引号 = $q3.Count
    短看着 = $kan.Count; 没说话 = $nosay.Count; 沉默 = $sil.Count; 极短对话 = $ack.Count
  }
}

function Get-Candidates {
  param($Paras)
  $list = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $Paras.Count; $i++) {
    $p = $Paras[$i]; $t = $p.Text
    $qCount = ([regex]::Matches($t, $QO)).Count

    if (-not $t.Contains($QO) -and $t -match '看着' -and $t.Length -le 30) {
      $list.Add([pscustomobject]@{ Line = $p.Line; Kind = 'A1'; Hint = '改动作/并入邻段/删'; Text = $t })
    }
    elseif (-not $t.Contains($QO) -and $t -match '没有说话|没说话|没有答话|没有回答' -and $t.Length -le 30) {
      $list.Add([pscustomobject]@{ Line = $p.Line; Kind = 'A2'; Hint = '删或改动作；有回响的留'; Text = $t })
    }
    elseif (-not $t.Contains($QO) -and $t -match '沉默' -and $t.Length -le 25) {
      $list.Add([pscustomobject]@{ Line = $p.Line; Kind = 'A2'; Hint = '删或改动作；有回响的留'; Text = $t })
    }

    if ($t.StartsWith($QO)) {
      $inner = $t -replace '^[' + $QO + $QC + ']', ''
      $inner = $inner -replace '[' + $QO + $QC + '].*$', ''
      if ($inner.Length -le 6) {
        $list.Add([pscustomobject]@{ Line = $p.Line; Kind = 'B1'; Hint = '看是否空转应答'; Text = $t })
      }
    }

    if ($qCount -ge 2) {
      # 用“引号 + 说/问/道”的归属语判断一段里换没换人；换了人 = 必须分段
      $spk = @()
      foreach ($m in [regex]::Matches($t, $Qc + '([^' + $Qo + $Qc + ']{0,4}?)(说|问|道|答|喊|叫|嚷|叹)')) {
        $sn = ($m.Groups[1].Value -replace '^[，。！？、；：\s]+', '' -replace '[，。！？、；：\s]+$', '')
        if ($sn -notmatch '[了的得地]') { $spk += $sn }
      }
      $uniq = @($spk | Where-Object { $_.Length -gt 0 } | Select-Object -Unique)
      if ($uniq.Count -ge 2) {
        $list.Add([pscustomobject]@{ Line = $p.Line; Kind = 'C1'; Hint = "换人：$($uniq -join ' / ') → 分段"; Text = $t })
      } elseif ($qCount -ge 3) {
        $list.Add([pscustomobject]@{ Line = $p.Line; Kind = 'C2'; Hint = '同人停顿续话，看是否过密'; Text = $t })
      }
    }

    if ($i -gt 0 -and $Paras[$i - 1].Text -eq $t) {
      $list.Add([pscustomobject]@{ Line = $p.Line; Kind = 'D1'; Hint = '重复段'; Text = $t })
    }
    if ($i -gt 0) {
      $a = $Paras[$i - 1].Text; $b = $t
      if ($a.StartsWith($QO) -and $b.StartsWith($QO) -and $a.Length -le 14 -and $b.Length -le 14) {
        $list.Add([pscustomobject]@{ Line = $p.Line; Kind = 'B2'; Hint = '短问短答：先判有无新信息'; Text = "$a ｜ $b" })
      }
    }
  }
  return ,$list
}

function Get-Chapters {
  param([string]$Sel)
  $all = 1..15 | ForEach-Object { if ($_ -lt 10) { "0$_" } else { "$_" } }
  if ($Sel -eq 'all') { return $all }
  $s = $Sel -replace '[^0-9]', ''
  if (-not $s) { throw "无法识别的章号：$Sel" }
  return @($s.PadLeft(2, '0'))
}

$chapters = Get-Chapters $Chapter
$rows = New-Object System.Collections.Generic.List[object]

foreach ($ch in $chapters) {
  $path = Join-Path $Root "正文\ch$ch.md"
  if (-not (Test-Path -LiteralPath $path)) { Write-Warning "缺文件：$path"; continue }
  $paras = Get-Paras -Path $path
  $m = Get-Metrics -Path $path -Paras $paras
  $cands = Get-Candidates -Paras $paras

  $rows.Add([pscustomobject]@{
    章 = "ch$ch"; 汉字 = $m.汉字; 段 = $m.段; 字每段 = $m.字每段; 对话段 = $m.对话段
    含3引号 = $m.含3引号; 短看着 = $m.短看着; 没说话 = $m.没说话; 沉默 = $m.沉默; 极短对话 = $m.极短对话; 候选 = $cands.Count
  })

  $md = New-Object System.Collections.Generic.List[string]
  $md.Add("# ch$ch 对话审计（D83）")
  $md.Add('')
  $md.Add("- 汉字 $($m.汉字)｜段 $($m.段)｜字/段 $($m.字每段)｜对话段 $($m.对话段)")
  $md.Add("- 含2引号段 $($m.含2引号)｜含3+引号段 $($m.含3引号)｜短看着段 $($m.短看着)｜没说话 $($m.没说话)｜沉默独立段 $($m.沉默)｜极短对话段 $($m.极短对话)")
  $md.Add("- 候选 $($cands.Count) 条（行号可直接作 read 的 offset）")
  $md.Add('')
  $md.Add('| 行 | 类型 | 提示 | 原文 |')
  $md.Add('|---|---|---|---|')
  foreach ($c in $cands) {
    $txt = $c.Text -replace '\|', '｜'
    if ($txt.Length -gt 110) { $txt = $txt.Substring(0, 110) + '…' }
    $md.Add("| $($c.Line) | $($c.Kind) | $($c.Hint) | $txt |")
  }
  $outFile = Join-Path $OutPath "ch$ch.audit.md"
  [IO.File]::WriteAllText($outFile, ($md -join "`r`n"), [Text.UTF8Encoding]::new($false))
}

if ($WriteBaseline) {
  $csv = $rows | ConvertTo-Csv -NoTypeInformation
  [IO.File]::WriteAllText((Join-Path $OutPath 'baseline.csv'), (($csv -join "`r`n") + "`r`n"), [Text.UTF8Encoding]::new($false))
  "已写基线：$OutPath\baseline.csv"
}

$rows | Format-Table -AutoSize | Out-String -Width 200
