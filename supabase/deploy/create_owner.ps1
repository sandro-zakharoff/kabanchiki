# Kabanchiki: create the first owner account on a fresh project.
#
# A brand-new project has no owner yet, and the 'admin' Edge Function requires an
# existing owner to create more. This one-time bootstrap uses the service_role
# key to create a confirmed auth user and its owner row directly.
#
# Usage:
#   .\create_owner.ps1 -ProjectRef xxxx -ServiceRoleKey 'eyJ...' -Email you@example.com
#                       [-DisplayName 'Your name'] [-Password 'optional']
#
# If -Password is omitted a strong one is generated and printed once. Change it
# from the desktop app after the first sign-in.

param(
    [Parameter(Mandatory = $true)][string]$ProjectRef,
    [Parameter(Mandatory = $true)][string]$ServiceRoleKey,
    [Parameter(Mandatory = $true)][string]$Email,
    [string]$DisplayName = "",
    [string]$Password = ""
)

$ErrorActionPreference = "Stop"
$base = "https://$ProjectRef.supabase.co"
$headers = @{
    "apikey"        = $ServiceRoleKey
    "Authorization" = "Bearer $ServiceRoleKey"
    "Content-Type"  = "application/json"
}

if (-not $Password) {
    $bytes = [byte[]]::new(18)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $Password = "Kab-" + [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("/", "_").Replace("+", "-")
}
if (-not $DisplayName) { $DisplayName = $Email.Split("@")[0] }

Write-Host "==> creating auth user $Email"
$userBody = @{
    email         = $Email
    password      = $Password
    email_confirm = $true
} | ConvertTo-Json
$user = Invoke-RestMethod -Method Post -Uri "$base/auth/v1/admin/users" -Headers $headers -Body $userBody
$uid = $user.id
if (-not $uid) { throw "Auth user was not created (no id returned)." }

Write-Host "==> registering owner row for $uid"
$parentBody = @{
    id           = $uid
    email        = $Email
    display_name = $DisplayName
    is_owner     = $true
} | ConvertTo-Json
$prefer = $headers.Clone()
$prefer["Prefer"] = "resolution=merge-duplicates"
Invoke-RestMethod -Method Post -Uri "$base/rest/v1/parents" -Headers $prefer -Body $parentBody | Out-Null

Write-Host ""
Write-Host "Owner created." -ForegroundColor Green
Write-Host "  Email:    $Email"
Write-Host "  Password: $Password"
Write-Host ""
Write-Host "Sign in with these in the desktop app, then change the password from" -ForegroundColor Yellow
Write-Host "Settings -> Account -> Change password." -ForegroundColor Yellow
