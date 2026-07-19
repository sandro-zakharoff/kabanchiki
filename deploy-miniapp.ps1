# Publishes the Telegram Mini App from this repository.
# GitHub Pages deployment is handled by .github/workflows/miniapp-pages.yml.
#
# Usage: double-click deploy-miniapp.bat, or run:
#   pwsh -File deploy-miniapp.ps1 "optional commit message"
param([string]$Message = "")
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSCommandPath
$Tg = Join-Path $Root "telegram"

# Bump cache-busters so Telegram and Pages do not reuse stale module files.
$edges = "index.html","config.js","js/app.js","js/api.js","js/ui.js","js/format.js","js/config.js","js/images.js"
$paths = $edges | ForEach-Object { Join-Path $Tg $_ } | Where-Object { Test-Path $_ }
$cur = 0
foreach ($path in $paths) {
  [regex]::Matches((Get-Content $path -Raw), '\?v=(\d+)') | ForEach-Object {
    $number = [int]$_.Groups[1].Value
    if ($number -gt $cur) { $cur = $number }
  }
}
if ($cur -eq 0) { throw "No ?v= markers found in $Tg — nothing to bump." }
$next = $cur + 1
foreach ($path in $paths) {
  Set-Content -NoNewline -Path $path -Value ([regex]::Replace((Get-Content $path -Raw), '\?v=\d+', "?v=$next"))
}
if (-not $Message) { $Message = "chore(miniapp): deploy v$next" }
Write-Host "== Mini App v$cur -> v$next ==" -ForegroundColor Cyan

Set-Location $Root
git add telegram/
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) { git commit -m $Message | Out-Null }
git push origin main
Write-Host "== source repo pushed ==" -ForegroundColor Green
Write-Host "GitHub Pages workflow will publish telegram/ from this repository." -ForegroundColor Green
