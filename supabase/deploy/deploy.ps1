# Kabanchiki: one-shot backend deployment.
# Usage:
#   .\deploy.ps1 -ProjectRef xxxx -DbPassword '...' -AccessToken 'sbp_...' `
#                -FcmServiceAccountPath 'C:\path\to\firebase-adminsdk.json'
#
# Steps:
#   1. supabase link
#   2. render outbox_webhook.sql.template into a migration (secret inside, gitignored)
#   3. supabase db push               (applies all supabase/migrations)
#   4. supabase secrets set           (FCM_SERVICE_ACCOUNT, WEBHOOK_SECRET)
#   5. supabase functions deploy send-push

param(
    [Parameter(Mandatory = $true)][string]$ProjectRef,
    [Parameter(Mandatory = $true)][string]$DbPassword,
    [Parameter(Mandatory = $true)][string]$AccessToken,
    [Parameter(Mandatory = $true)][string]$FcmServiceAccountPath
)

$ErrorActionPreference = 'Stop'
$supa = "$env:LOCALAPPDATA\KabanchikiTools\supabase-cli\supabase.exe"
$repo = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
$env:SUPABASE_ACCESS_TOKEN = $AccessToken
$env:SUPABASE_DB_PASSWORD = $DbPassword

Set-Location $repo

Write-Host "==> linking project $ProjectRef"
& $supa link --project-ref $ProjectRef

Write-Host "==> rendering outbox webhook migration"
$secretFile = Join-Path $PSScriptRoot 'webhook_secret.secret'
if (Test-Path $secretFile) {
    $webhookSecret = (Get-Content $secretFile -Raw).Trim()
} else {
    $webhookSecret = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
    Set-Content $secretFile $webhookSecret -Encoding ascii
}
$template = Get-Content (Join-Path $PSScriptRoot 'outbox_webhook.sql.template') -Raw
$sql = $template.Replace('{{PROJECT_REF}}', $ProjectRef).Replace('{{WEBHOOK_SECRET}}', $webhookSecret)
Set-Content (Join-Path $repo 'supabase\migrations\20260714130000_outbox_webhook.sql') $sql -Encoding utf8
$tgTemplate = Get-Content (Join-Path $PSScriptRoot 'tg_webhook.sql.template') -Raw
$tgSql = $tgTemplate.Replace('{{PROJECT_REF}}', $ProjectRef).Replace('{{WEBHOOK_SECRET}}', $webhookSecret)
Set-Content (Join-Path $repo 'supabase\migrations\20260718130000_tg_webhook.sql') $tgSql -Encoding utf8

Write-Host "==> pushing migrations"
& $supa db push

Write-Host "==> setting function secrets"
$fcmJson = Get-Content $FcmServiceAccountPath -Raw
& $supa secrets set "WEBHOOK_SECRET=$webhookSecret" "FCM_SERVICE_ACCOUNT=$fcmJson"

Write-Host "==> deploying send-push"
& $supa functions deploy send-push
Write-Host "==> deploying Telegram functions"
& $supa functions deploy tg-notify
& $supa functions deploy tg-bot

Write-Host "==> done"
