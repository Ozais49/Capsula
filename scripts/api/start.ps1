<#
.SYNOPSIS
Starts the Capsula API server on this computer.

.DESCRIPTION
Gets the server's dependencies and runs it on http://localhost:8787 (stop it with
Ctrl+C).

-Mode emulators (the default) starts the local Firebase emulators too, in their own
window, and keeps all data local. -Mode live uses the real Firebase project and needs
a service account key: pass -Credentials, set GOOGLE_APPLICATION_CREDENTIALS, or put
the key in api\secrets\ (ignored by git).

A phone started with scripts\phone\run.ps1 -Config emulators reaches this server at
http://localhost:8787 over USB. Set that address in the app under
Settings > API & integrations.

.EXAMPLE
.\scripts\api\start.ps1
.\scripts\api\start.ps1 -Mode live -Credentials C:\keys\capsula-service-account.json
.\scripts\api\start.ps1 -Port 9000
#>
param(
    [ValidateSet('emulators', 'live')]
    [string] $Mode = 'emulators',

    [int] $Port = 8787,

    # Service account key (JSON) for -Mode live.
    [string] $Credentials,

    # Firebase project for -Mode live.
    [string] $Project = 'capsula-ygtech',

    # Browser origins allowed to call the API, comma-separated.
    [string] $CorsOrigins = '*'
)

. "$PSScriptRoot\..\common.ps1"

$dart = Find-Dart

if (Test-Port $Port) {
    Stop-WithError "Port $Port is in use (is the server already running?). Use -Port to pick another."
}

Write-Step 'Getting API dependencies'
Push-Location $ApiDir
try { Invoke-Tool $dart @('pub', 'get') } finally { Pop-Location }

# Settings for the server process (see api/README.md).
$env:PORT = "$Port"
$env:CORS_ORIGINS = $CorsOrigins
if ($Mode -eq 'emulators') {
    Start-FirebaseEmulators $EmulatorProject
    $env:FIREBASE_PROJECT_ID = $EmulatorProject
    $env:USE_FIREBASE_EMULATORS = 'true'
    Remove-Item Env:GOOGLE_APPLICATION_CREDENTIALS -ErrorAction SilentlyContinue
} else {
    if (-not $Credentials) { $Credentials = $env:GOOGLE_APPLICATION_CREDENTIALS }
    if (-not $Credentials) {
        $Credentials = Get-ChildItem (Join-Path $ApiDir 'secrets') -Filter '*.json' -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $Credentials -or -not (Test-Path $Credentials)) {
        Stop-WithError ('-Mode live needs a service account key. In the Firebase console: Project ' +
            'settings > Service accounts > Generate new private key. Save it in api\secrets\ ' +
            'or pass -Credentials <path>. Keep it secret.')
    }
    $env:FIREBASE_PROJECT_ID = $Project
    $env:GOOGLE_APPLICATION_CREDENTIALS = (Resolve-Path $Credentials).Path
    $env:USE_FIREBASE_EMULATORS = 'false'
}

Write-Step "Starting the API server ($Mode) on http://localhost:$Port. Press Ctrl+C to stop."
Write-Host "Check it: http://localhost:$Port/v1/health"
Push-Location $ApiDir
try { Invoke-Tool $dart @('run', 'bin/server.dart') } finally { Pop-Location }
