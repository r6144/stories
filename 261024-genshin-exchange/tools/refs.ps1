# 改一处，找全部引用
# 用法：pwsh -NoProfile -File tools\refs.ps1 "D79"        # 查决策编号
#       pwsh -NoProfile -File tools\refs.ps1 "瓦萨里回廊"  # 查一个设定/名词
# 只读，不改文件。

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Pattern
)

$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path

$files = @('AGENTS.md', 'README.md')
$files += Get-ChildItem 'docs', 'research', '.agents', 'tools' -Recurse -File -Include *.md, *.ps1 |
    Where-Object { $_.FullName -notmatch '\\90-归档\\' } |
    ForEach-Object { $_.FullName.Substring($root.Length + 1) -replace '\\', '/' }

$hits = @()
foreach ($f in $files) {
    $t = [System.IO.File]::ReadAllText((Join-Path $root $f))
    $lines = $t -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -like "*$Pattern*") {
            $hits += [PSCustomObject]@{ File = $f; Line = $i + 1; Text = $lines[$i].Trim() }
        }
    }
}

Write-Output "=== 引用：$Pattern ==="
if ($hits.Count -eq 0) {
    Write-Output '（没有任何文件提到它——要么是新增内容，要么是已失效的旧名）'
    exit 0
}

$hits | Group-Object File | Sort-Object Name | ForEach-Object {
    Write-Output ("{0}  ({1} 处)" -f $_.Name, $_.Count)
    $_.Group | Select-Object -First 6 | ForEach-Object {
        $t = if ($_.Text.Length -gt 100) { $_.Text.Substring(0, 100) + '…' } else { $_.Text }
        Write-Output ("    {0,5}: {1}" -f $_.Line, $t)
    }
}
Write-Output ''
Write-Output ("合计 {0} 处，{1} 个文件。" -f $hits.Count, ($hits | Group-Object File).Count)
Write-Output '改设定时：先改 SSOT → 看这里列出的文件 → 只改会被误导的地方 → 跑 tools\docs-lint.ps1。'
