param(
    [string]$Path = (Join-Path $PSScriptRoot '..\正文')
)

# 粗略统计章节风格：字数、段落、对话比例、句长。
# 用法：pwsh -File tools/style_metrics.ps1 -Path 正文/ch01.md
#       pwsh -File tools/style_metrics.ps1 -Path 正文

if (-not (Test-Path $Path)) {
    Write-Host "没有找到：$Path"
    exit 0
}

$item = Get-Item $Path
if ($item.PSIsContainer) {
    $files = Get-ChildItem -Path $item.FullName -Filter '*.md' -File | Sort-Object Name
} else {
    $files = @($item)
}

if (-not $files -or $files.Count -eq 0) {
    Write-Host "没有 .md 文件。"
    exit 0
}

$rows = foreach ($f in $files) {
    $text = Get-Content -Raw -Encoding UTF8 $f.FullName
    $plain = $text -replace '(?m)^#{1,6}\s.*$', '' -replace '\*\*|__|`|>', ''
    $total = ($plain -replace '\s', '').Length

    $paras = @([regex]::Split($plain, '\r?\n\s*\r?\n') | Where-Object { $_.Trim().Length -gt 0 })
    $paraLens = @($paras | ForEach-Object { ($_ -replace '\s', '').Length })
    $paraCount = $paras.Count
    $avgPara = if ($paraCount -gt 0) { [math]::Round((($paraLens | Measure-Object -Average).Average), 1) } else { 0 }
    $short = @($paraLens | Where-Object { $_ -lt 40 }).Count
    $long = @($paraLens | Where-Object { $_ -gt 350 }).Count
    $shortPct = if ($paraCount -gt 0) { [math]::Round(100 * $short / $paraCount, 1) } else { 0 }
    $longPct = if ($paraCount -gt 0) { [math]::Round(100 * $long / $paraCount, 1) } else { 0 }

    $dialogChars = 0
    foreach ($m in [regex]::Matches($plain, '[“「](.*?)[”」]', 'Singleline')) {
        $dialogChars += ($m.Groups[1].Value -replace '\s', '').Length
    }
    $dialoguePct = if ($total -gt 0) { [math]::Round(100 * $dialogChars / $total, 1) } else { 0 }

    $sentences = @([regex]::Split($plain, '[。！？!?]') | Where-Object { $_.Trim().Length -gt 0 })
    $sentLens = @($sentences | ForEach-Object { ($_ -replace '\s', '').Length })
    $avgSent = if ($sentences.Count -gt 0) { [math]::Round((($sentLens | Measure-Object -Average).Average), 1) } else { 0 }

    [pscustomobject]@{
        File      = $f.Name
        Chars     = $total
        Paras     = $paraCount
        AvgPara   = $avgPara
        ShortPct  = $shortPct
        LongPct   = $longPct
        Dialogue  = $dialoguePct
        AvgSent   = $avgSent
    }
}

$rows | Format-Table -AutoSize

Write-Host ""
Write-Host "目标：Chars 9000-11000 | AvgPara 100-180 | ShortPct <15 | LongPct <10 | Dialogue 35-45 | AvgSent 18-30"

