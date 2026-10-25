param(
    [string]$Path = (Join-Path $PSScriptRoot '..\正文')
)

# 粗略统计中文正文字数：去掉 Markdown 标记、空白、标题行，只数汉字/标点。
# 可选工具：只用于大致确认章节落在 8k-16k 附近；不是验收指标，不作为改文依据。

if (-not (Test-Path $Path)) {
    Write-Host "没有找到正文目录：$Path"
    exit 0
}

$files = Get-ChildItem -Path $Path -Filter '*.md' -File | Sort-Object Name
if (-not $files) {
    Write-Host "正文目录里还没有 .md 文件。"
    exit 0
}

$total = 0
foreach ($f in $files) {
    $text = Get-Content -Raw -Encoding UTF8 $f.FullName
    $text = $text -replace '(?m)^#{1,6}\s.*$', ''
    $text = $text -replace '[`*_>#\-\[\]\(\)]', ''
    $count = ($text -replace '\s', '').Length
    $total += $count
    '{0,-28} {1,8}' -f $f.Name, $count
}
'{0,-28} {1,8}' -f '合计', $total

