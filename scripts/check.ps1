# Kabanchiki — run every code-quality gate locally, the same ones CI runs.
#
#   pwsh -File scripts/check.ps1
#
# Checks: Python lint (ruff), Python format (ruff format --check), Python tests
# (pytest), and a quick secret scan of the Mini App. Exits non-zero on the first
# failure so it is safe to use in a pre-push hook.

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Section($name) { Write-Host "`n== $name ==" -ForegroundColor Cyan }

Section "Python lint (ruff)"
python -m ruff check desktop/src desktop/tests

Section "Python format (ruff format --check)"
python -m ruff format --check desktop/src desktop/tests

Section "Python tests (pytest)"
python -m pytest desktop/tests -q

Section "Mini App secret scan"
$hits = Select-String -Path telegram/js/*.js, telegram/config.js `
    -Pattern 'service_role|client_secret|-----BEGIN|bot[_-]?token\s*[:=]' -SimpleMatch:$false
if ($hits) {
    $hits | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }
    throw "Potential secret found in the Mini App bundle."
}
Write-Host "no secrets found" -ForegroundColor Green

Write-Host "`nAll checks passed." -ForegroundColor Green
