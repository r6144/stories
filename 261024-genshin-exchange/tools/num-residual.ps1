# 残留扫描：找出脚本规则覆盖不到、需要人工判断的数字写法。
# 输出：R1 引语内阿拉伯大数；R2 叙述内汉字 10–99；R3 钟点；R4 汉字金额；R5 第X章/节；R6 跨行引语可疑行
param([string]$Path = '正文')

$ErrorActionPreference = 'Stop'
$uN = '个月|分钟|小时|公里|天|年|个|次|只|岁|秒|遍|句|支|瓶|杯|碗|双|人|步|米|里|封|张|把|件|页|层|间|位|颗|根|片|块|段|条|声|下|口|座|辆|头|箱|袋|包|桶|桌|斤|圈|场|份|笔|滴|棵|株|朵|瓣|枝|面|尊|匹|尾|粒|枚|种|类|样|群|批|队|对|套|副|艘|架|台|门|盏|沓|摞|排|行|列|趟|轮|顶|寸|尺|丈'

function Ctx([string]$line, [int]$idx, [int]$len) {
    $s = [Math]::Max(0, $idx - 22)
    $e = [Math]::Min($line.Length, $idx + $len + 22)
    return ($line.Substring($s, $e - $s) -replace "`t", ' ')
}
function InQ([string]$line, [int]$idx) {
    $h = $line.Substring(0, $idx)
    return (([regex]::Matches($h, '“')).Count -gt ([regex]::Matches($h, '”')).Count)
}

$files = Get-ChildItem -LiteralPath $Path -Filter '*.md' | Sort-Object Name
$out = New-Object System.Collections.ArrayList
foreach ($f in $files) {
    $lines = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) -split "`r?`n"
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $ln = $i + 1
        # R1 引语内阿拉伯 >=10
        foreach ($m in [regex]::Matches($line, "(?<![\d.])(\d{2,}|\d)\s*($uN)")) {
            if ([double]$m.Groups[1].Value -lt 10) { continue }
            if (-not (InQ $line $m.Index)) { continue }
            [void]$out.Add(("{0}:{1}  R1  {2}" -f $f.Name, $ln, (Ctx $line $m.Index $m.Length)))
        }
        # R2 叙述内汉字 10–99
        foreach ($m in [regex]::Matches($line, "(十[一二三四五六七八九]|[一二三四五六七八九]十[一二三四五六七八九]?)(?![多几余来百千万])(?=$uN)")) {
            if (InQ $line $m.Index) { continue }
            [void]$out.Add(("{0}:{1}  R2  {2}" -f $f.Name, $ln, (Ctx $line $m.Index $m.Length)))
        }
        # R3 钟点
        foreach ($m in [regex]::Matches($line, "\d+\s*点")) {
            [void]$out.Add(("{0}:{1}  R3  {2}" -f $f.Name, $ln, (Ctx $line $m.Index $m.Length)))
        }
        # R4 汉字金额
        foreach ($m in [regex]::Matches($line, "[一二三四五六七八九十百千万两]+\s*(万|千)?\s*摩拉")) {
            [void]$out.Add(("{0}:{1}  R4  {2}" -f $f.Name, $ln, (Ctx $line $m.Index $m.Length)))
        }
        # R5 第X章/节
        foreach ($m in [regex]::Matches($line, "第\s*[0-9一二三四五六七八九十]+\s*[章节]")) {
            [void]$out.Add(("{0}:{1}  R5  {2}" -f $f.Name, $ln, (Ctx $line $m.Index $m.Length)))
        }
    }
}
$outFile = Join-Path $PSScriptRoot '_num-residual.txt'
($out -join "`r`n") | Set-Content -LiteralPath $outFile -Encoding UTF8
"残留 {0} 条 -> tools\_num-residual.txt" -f $out.Count
$out | Group-Object { ($_ -split '  ')[1] } | ForEach-Object { "{0}: {1}" -f $_.Name, $_.Count }
