# 引语数字修补：把引语内的阿拉伯数字（1–99）改成汉字；日期、金额、记录式“第X天”（≥100）保留。
# 另含少量逐行指定修补。
param([string]$Path = '正文')

$ErrorActionPreference = 'Stop'
$uQ = '个月|分钟|小时|公里|天|年|个|次|只|岁|秒|遍|句|支|瓶|杯|碗|双|人|步|米|里|封|张|把|件|页|层|间|位|颗|根|片|块|段|条|声|下|口|座|辆|头|箱|袋|包|桶|桌|斤|圈|场|份|笔|滴|棵|株|朵|瓣|枝|面|尊|匹|尾|粒|枚|种|类|样|群|批|队|对|套|副|艘|架|台|门|盏|沓|摞|排|行|列|趟|轮|顶|寸|尺|丈|周|礼拜|楼|刻|级|盘|倍|本|道|夜|壶'
$rx = [regex]"(?<![\d.])(\d{1,3})\s*($uQ)"

function Num2Cn([int]$n) {
    $d = '零一二三四五六七八九'
    if ($n -lt 0) { return [string]$n }
    if ($n -eq 0) { return '零' }
    if ($n -eq 2) { return '两' }
    if ($n -lt 10) { return [string]$d[$n] }
    if ($n -lt 20) { if ($n -eq 10) { return '十' } return '十' + [string]$d[$n - 10] }
    if ($n -lt 100) {
        $t = [math]::Floor($n / 10); $r = $n % 10
        if ($r -eq 0) { return [string]$d[$t] + '十' }
        return [string]$d[$t] + '十' + [string]$d[$r]
    }
    if ($n -lt 1000) {
        $h = [math]::Floor($n / 100); $r = $n % 100
        $hs = if ($h -eq 2) { '两' } else { [string]$d[$h] }
        if ($r -eq 0) { return $hs + '百' }
        if ($r -lt 10) { return $hs + '百零' + [string]$d[$r] }
        return $hs + '百' + (Num2Cn $r)
    }
    return [string]$n
}

# 跳过：这些行里的数字是原作引文/日期，保持阿拉伯
$skipLines = @{ 'ch15.md:622' = 1 }
# 逐行定点修补：文件|行号|旧|新
$manual = @(
    @('ch09.md', 329, '下午4点，案子翻了', '下午四点，案子翻了'),
    @('ch09.md', 911, '第二天早上6点，铃响了', '第二天早上六点，铃响了'),
    @('ch04.md', 471, '她愿意用一万摩拉换一碗热汤', '她愿意用1万摩拉换一碗热汤'),
    @('ch10.md', 797, '她想了想。“447天。”', '她想了想。“四百四十七天。”')
)

$files = Get-ChildItem -LiteralPath $Path -Filter '*.md' | Sort-Object Name
$count = 0
foreach ($f in $files) {
    $raw = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $raw -split "`r?`n"
    $dirty = $false
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $no = $i + 1
        $line = $lines[$i]
        $orig = $line
        $key = "$($f.Name):$no"
        if (-not $skipLines.ContainsKey($key)) {
            # 引语内 1–99 → 汉字
            $sb = New-Object System.Text.StringBuilder
            $pos = 0; $hit = $false
            foreach ($m in $rx.Matches($line)) {
                $idx = $m.Index
                if ($idx -lt $pos) { continue }
                $head = $line.Substring(0, $idx)
                $inQ = ([regex]::Matches($head, '“')).Count -gt ([regex]::Matches($head, '”')).Count
                if (-not $inQ) { continue }
                $unit = $m.Groups[2].Value
                if ($unit -in @('块', '元') ) { continue }
                $v = [int]$m.Groups[1].Value
                
                if ($head.TrimEnd().EndsWith('第') -and $v -ge 100) { continue }
                $sb.Append($line.Substring($pos, $idx - $pos)).Append((Num2Cn $v)).Append($unit) | Out-Null
                $pos = $idx + $m.Length
                $hit = $true; $count++
            }
            if ($hit) { $sb.Append($line.Substring($pos)) | Out-Null; $line = $sb.ToString() }
        }
        foreach ($mm in $manual) {
            if ($mm[0] -eq $f.Name -and [int]$mm[1] -eq $no) {
                if ($line.Contains($mm[2])) { $line = $line.Replace($mm[2], $mm[3]); $count++ }
                else { Write-Warning ("定点修补未命中 {0}:{1} -> {2}" -f $f.Name, $no, $mm[2]) }
            }
        }
        if ($line -ne $orig) { $lines[$i] = $line; $dirty = $true }
    }
    if ($dirty) { [IO.File]::WriteAllText($f.FullName, ($lines -join $nl), (New-Object Text.UTF8Encoding($false))) }
}
"修补 {0} 处" -f $count
