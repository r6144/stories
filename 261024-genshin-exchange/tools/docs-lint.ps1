# 文档校验：预算、引用完整性、日志残留、跨文件重复、卡片栏目
# 用法：pwsh -NoProfile -File tools\docs-lint.ps1
# 退出码：0 = 通过（可能有 WARN）；1 = 有 FAIL

$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
Set-Location $root

function Get-Chars([string]$path) {
    $t = [System.IO.File]::ReadAllText((Join-Path $root $path))
    return ($t -replace '\s', '').Length
}

$fail = New-Object System.Collections.ArrayList
$warn = New-Object System.Collections.ArrayList

# ---------- 1. 字数预算 ----------
$budgets = @{
    'AGENTS.md'                = 7000
    'README.md'                = 2500
    'docs/02-章节大纲.md'       = 4500
    'docs/06-写作规范.md'       = 8000
    'docs/09-声音与节奏.md'     = 4000
    'docs/10-进度与事实账本.md' = 15000
}
foreach ($k in $budgets.Keys) {
    if (-not (Test-Path $k)) { [void]$fail.Add("预算表里的文件不存在：$k"); continue }
    $c = Get-Chars $k
    if ($c -gt $budgets[$k]) { [void]$fail.Add("超预算：$k $c / $($budgets[$k])") }
}

Get-ChildItem 'docs/08-章节写作包/ch*.md' | ForEach-Object {
    $c = Get-Chars ($_.FullName.Substring($root.Length + 1) -replace '\\', '/')
    if ($c -gt 3200) { [void]$fail.Add("卡片超预算：$($_.Name) $c / 3200") }
}

# ---------- 2. 账本 ----------
$ten = [System.IO.File]::ReadAllText((Join-Path $root 'docs/10-进度与事实账本.md')) -replace '\s', ''
$ledgerCount = ([regex]::Matches($ten, '###ch\d\d事实账本')).Count
if ($ledgerCount -ne 15) { [void]$fail.Add("账本应有 15 段，实际 $ledgerCount") }

$text10 = [System.IO.File]::ReadAllText((Join-Path $root 'docs/10-进度与事实账本.md'))
$blocks = [regex]::Matches($text10, '(?ms)^### (ch\d\d) 事实账本\n(.*?)(?=^### |\z)')
foreach ($b in $blocks) {
    $len = ($b.Groups[2].Value -replace '\s', '').Length
    if ($len -gt 900) { [void]$fail.Add("账本超预算：$($b.Groups[1].Value) $len / 900") }
}

# ---------- 3. 路径引用是否存在 ----------
$docs = @('AGENTS.md', 'README.md')
$docs += Get-ChildItem 'docs', '.agents', 'research' -Recurse -File -Filter *.md |
    Where-Object { $_.FullName -notmatch '\\90-归档\\' } |
    ForEach-Object { $_.FullName.Substring($root.Length + 1) -replace '\\', '/' }

$badRefs = @{}
foreach ($f in $docs) {
    $t = [System.IO.File]::ReadAllText((Join-Path $root $f))
    foreach ($m in [regex]::Matches($t, '(docs|research|tools|\.agents)/([0-9A-Za-z\u4e00-\u9fa5._\-/]+\.(md|ps1))')) {
        $p = $m.Value
        if ($p -match 'chXX|chxx') { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $root $p))) {
            if (-not $badRefs.ContainsKey($p)) { $badRefs[$p] = @() }
            $badRefs[$p] += $f
        }
    }
}
foreach ($k in $badRefs.Keys) { [void]$fail.Add("引用不存在：$k（$($badRefs[$k] -join ', ')）") }

# ---------- 4. 日志残留 ----------
foreach ($f in @('AGENTS.md', 'README.md')) {
    $t = [System.IO.File]::ReadAllText((Join-Path $root $f))
    if ($t -match '(?m)^\s*-\s*\[[ x]\]') { [void]$fail.Add("$f 里有进度清单（- [x]），进度只写 docs/10 的进度表") }
}
foreach ($f in $docs) {
    if ($f -like 'docs/90-*') { continue }
    $t = [System.IO.File]::ReadAllText((Join-Path $root $f))
    if ($t -match '\d{4}-\d{2}-\d{2}（D\d') { [void]$warn.Add("$f 里有日期式执行日志") }
}

# ---------- 5. 卡片栏目 ----------
$forbidden = @('人物声音', '声音锚点', 'Canon 锚点', '引号与格式', '上一章事实账本', '开头选项', '本次修改清单')
Get-ChildItem 'docs/08-章节写作包/ch*.md' | ForEach-Object {
    $t = [System.IO.File]::ReadAllText($_.FullName)
    foreach ($w in $forbidden) {
        if ($t.Contains($w)) { [void]$fail.Add("$($_.Name) 残留旧栏目：$w") }
    }
    foreach ($h in @('## 一句话', '## 时间 / 地点 / POV', '## 本章目标', '## Beat', '## 人物与写法边界', '## 本章的坑', '## 结尾钩子', '## 需要时核对')) {
        if (-not $t.Contains($h)) { [void]$fail.Add("$($_.Name) 缺栏目：$h") }
    }
}

# ---------- 6. 跨文件重复段落（>=150 字） ----------
$norm = { param($s) (($s -replace '\s', '') -replace '[“”"「」『』]', '') }
$map = @{}
foreach ($f in $docs) {
    $raw = [System.IO.File]::ReadAllText((Join-Path $root $f))
    foreach ($p in ($raw -split "(\r?\n){2,}")) {
        $n = & $norm $p
        if ($n.Length -lt 150) { continue }
        if (-not $map.ContainsKey($n)) { $map[$n] = New-Object System.Collections.ArrayList }
        [void]$map[$n].Add($f)
    }
}
foreach ($k in $map.Keys) {
    $fs = @($map[$k] | Select-Object -Unique)
    if ($fs.Count -ge 2) { [void]$warn.Add("重复段落（$($k.Length) 字）：$($fs -join ' | ')") }
}

# ---------- 7. D 编号引用 ----------
$seven = [System.IO.File]::ReadAllText((Join-Path $root 'docs/07-待确认问题.md'))
$defined = @{}
foreach ($m in [regex]::Matches($seven, 'D(\d{1,2})')) { $defined[[int]$m.Groups[1].Value] = 1 }
foreach ($f in $docs) {
    $t = [System.IO.File]::ReadAllText((Join-Path $root $f))
    foreach ($m in [regex]::Matches($t, '(?<![A-Za-z\u4e00-\u9fa5])D(\d{1,2})(?![0-9])')) {
        $id = [int]$m.Groups[1].Value
        if (-not $defined.ContainsKey($id)) { [void]$warn.Add("$f 引用了未定义的 D$id") }
    }
}

# ---------- 输出 ----------
Write-Output "=== docs-lint ==="
if ($warn.Count -gt 0) {
    Write-Output "WARN ($($warn.Count)):"
    $warn | Sort-Object -Unique | ForEach-Object { Write-Output "  - $_" }
}
if ($fail.Count -gt 0) {
    Write-Output "FAIL ($($fail.Count)):"
    $fail | Sort-Object -Unique | ForEach-Object { Write-Output "  - $_" }
    exit 1
}
Write-Output "PASS（0 FAIL / $($warn.Count) WARN）"
exit 0
