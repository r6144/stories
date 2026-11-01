# 正文数字规范引擎：报告 / 改写 两种模式，同一套规则。
# A. 阿拉伯数字 1–9 + 量词（叙述、引语都改）→ 汉字；排除 初/星期/礼拜/农历/日期(月日号)。
#    “第 2 天”这类序数：2 在“第”后写作“二”（第二天）。
# B. 汉字数字 10–99 + 量词（仅叙述）→ 阿拉伯；排除引语、初/农历、约数(多/几/余/来)、百千万、钟点。
# C. 去空格（可选）：数字与量词、数字与前后汉字之间不留空格。
# 用法:
#   powershell -File tools\num-normalize.ps1                        # 全量报告（不写文件）
#   powershell -File tools\num-normalize.ps1 -Apply -NormalizeSpace  # 全量改写
#   powershell -File tools\num-normalize.ps1 -Path 正文\ch07.md -From 1 -To 140 -Apply -NormalizeSpace
param(
    [string]$Path = '正文',
    [switch]$Apply,
    [switch]$NormalizeSpace,
    [int]$From = 0,
    [int]$To = 0,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$uN = '个月|分钟|小时|公里|天|年|个|次|只|岁|秒|遍|句|支|瓶|杯|碗|双|人|步|米|里|封|张|把|件|页|层|间|位|颗|根|片|块|段|条|声|下|口|座|辆|头|箱|袋|包|桶|桌|斤|圈|场|份|笔|滴|棵|株|朵|瓣|枝|面|尊|匹|尾|粒|枚|种|类|样|群|批|队|对|套|副|艘|架|台|门|盏|句|沓|摞|排|行|列|趟|轮|顶|副|套|寸|尺|丈|周|礼拜|股|楼|刻|级|盘|倍|本|道|夜|壶'
$uA = $uN
$uB = $uN
$uC = $uN + '|点|分|月|日|号|章|节|摩拉|万|千'

$cnDigit = @{ '一' = 1; '二' = 2; '两' = 2; '三' = 3; '四' = 4; '五' = 5; '六' = 6; '七' = 7; '八' = 8; '九' = 9 }
$arDigit = @{ '1' = '一'; '2' = '两'; '3' = '三'; '4' = '四'; '5' = '五'; '6' = '六'; '7' = '七'; '8' = '八'; '9' = '九' }

$rxA = [regex]"(?<![\d.])([1-9])\s*($uA)"
$rxB = [regex]"(十[一二三四五六七八九]|[一二三四五六七八九]十[一二三四五六七八九]?)(?![多几余来百千万])(?=$uB)"

function In-Quote([string]$line, [int]$idx) {
    $head = $line.Substring(0, $idx)
    return (([regex]::Matches($head, '“')).Count -gt ([regex]::Matches($head, '”')).Count)
}

$files = @()
if (Test-Path -LiteralPath $Path -PathType Container) {
    $files = @(Get-ChildItem -LiteralPath $Path -Filter '*.md' | Sort-Object Name)
}
else {
    $files = @(Get-Item -LiteralPath $Path)
}

$totalA = 0; $totalB = 0; $totalC = 0; $totalLines = 0
$report = New-Object System.Collections.ArrayList

foreach ($f in $files) {
    $raw = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $raw -split "`r?`n"
    $fA = 0; $fB = 0; $fC = 0; $fLines = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $lineNo = $i + 1
        if ($From -gt 0 -and $lineNo -lt $From) { continue }
        if ($To -gt 0 -and $lineNo -gt $To) { continue }
        $line = $lines[$i]
        $orig = $line

        if ($NormalizeSpace) {
            $new = [regex]::Replace($line, "\s*(\d+)\s*($uC)", '$1$2')
            if ($new -ne $line) { $fC++; $line = $new }
        }

        # A：阿拉伯 1–9 → 汉字
        $sb = New-Object System.Text.StringBuilder
        $pos = 0
        $hitA = $false
        foreach ($m in $rxA.Matches($line)) {
            $idx = $m.Index
            if ($idx -lt $pos) { continue }
            $pre = $line.Substring(0, $idx).TrimEnd()
            if ($pre -match '(初|星期|礼拜|农历)$') { continue }
            $dig = $m.Groups[1].Value
            $cn = if ($dig -eq '2' -and ($pre.EndsWith('第') -or $m.Groups[2].Value -eq '楼')) { '二' } else { $arDigit[$dig] }
            $sb.Append($line.Substring($pos, $idx - $pos)) | Out-Null
            $sb.Append($cn) | Out-Null
            $sb.Append($m.Groups[2].Value) | Out-Null
            $pos = $idx + $m.Length
            $hitA = $true; $fA++
        }
        if ($hitA) {
            $sb.Append($line.Substring($pos)) | Out-Null
            $line = $sb.ToString()
        }

        # B：汉字 10–99 → 阿拉伯（仅叙述）
        $open = ([regex]::Matches($line, '“')).Count
        $close = ([regex]::Matches($line, '”')).Count
        if ($open -eq $close -and $rxB.IsMatch($line)) {
            $sb2 = New-Object System.Text.StringBuilder
            $pos2 = 0
            $hitB = $false
            foreach ($m in $rxB.Matches($line)) {
                $idx = $m.Index
                if ($idx -lt $pos2) { continue }
                if (In-Quote $line $idx) { continue }
                $pre2 = $line.Substring(0, $idx).TrimEnd()
                if ($pre2 -match '(初|农历)$') { continue }
                $v = $m.Groups[1].Value
                $n = $null
                if ($v -match '^十(.)$') { $n = 10 + $cnDigit[$Matches[1]] }
                elseif ($v -match '^(.)十(.)$') { $n = $cnDigit[$Matches[1]] * 10 + $cnDigit[$Matches[2]] }
                elseif ($v -match '^(.)十$') { $n = $cnDigit[$Matches[1]] * 10 }
                if ($null -eq $n) { continue }
                $sb2.Append($line.Substring($pos2, $idx - $pos2)) | Out-Null
                $sb2.Append([string]$n) | Out-Null
                $pos2 = $idx + $m.Length
                $hitB = $true; $fB++
            }
            if ($hitB) {
                $sb2.Append($line.Substring($pos2)) | Out-Null
                $line = $sb2.ToString()
            }
        }

        if ($line -ne $orig) {
            $fLines++
            [void]$report.Add([pscustomobject]@{ File = $f.Name; Line = $lineNo; Old = $orig; New = $line })
            $lines[$i] = $line
        }
    }

    if ($Apply -and $fLines -gt 0) {
        [IO.File]::WriteAllText($f.FullName, ($lines -join $nl), (New-Object Text.UTF8Encoding($false)))
    }
    $totalA += $fA; $totalB += $fB; $totalC += $fC; $totalLines += $fLines
    if (-not $Quiet) { "{0,-10} 行 {1,4}  A {2,-4} B {3,-4} C {4,-4}" -f $f.Name, $fLines, $fA, $fB, $fC }
}

"合计：行 {0}，A {1}，B {2}，C {3}，模式 {4}" -f $totalLines, $totalA, $totalB, $totalC, $(if ($Apply) { '已写入' } else { '仅报告' })

$out = Join-Path $PSScriptRoot '_num-report.txt'
($report | ForEach-Object { "{0}:{1}`t旧 {2}`t新 {3}" -f $_.File, $_.Line, $_.Old, $_.New }) -join "`r`n" |
    Set-Content -LiteralPath $out -Encoding UTF8
"报告：tools\_num-report.txt"
