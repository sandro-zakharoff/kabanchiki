param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-Location $Root

$tracked = git ls-files
$source = $tracked | Where-Object {
  $_ -notmatch '^(docs|README\.md$)' -and
  $_ -notmatch '\.(png|webp|ogg|qm|apk|jar)$'
}

$findings = @()
foreach ($file in $source) {
  $path = Join-Path $Root $file
  if (-not (Test-Path -LiteralPath $path)) { continue }
  $content = Get-Content -LiteralPath $path -Raw
  if ($null -eq $content) { continue }
  $patterns = @(
    '(?s)-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----\s*[A-Za-z0-9+/=]{40,}\s*-----END',
    '(?i)(service_role|client_secret|bot_token|password)\s*[:=]\s*["''][^"'']{8,}',
    '(?i)C:\\Users\\[^"'']+'
  )
  foreach ($pattern in $patterns) {
    if ([regex]::IsMatch($content, $pattern)) {
      $findings += "${file}: matched $pattern"
    }
  }
}

if ($findings.Count -gt 0) {
  $findings | ForEach-Object { Write-Output $_.ToString() }
  throw "Potential production secrets or machine-local paths found."
}

Write-Output "Production source scan passed: no private keys, secret assignments, or C:\Users paths found."
