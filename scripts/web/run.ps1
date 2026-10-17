<#
.SYNOPSIS
Runs the Capsula web app in a browser, with hot reload.

.DESCRIPTION
Gets dependencies and starts the app from source in Chrome or Edge. While it runs,
press r to hot reload, R to hot restart and q to quit.

Run locally, the web app isn't on Firebase Hosting, so the first time it asks for the
Firebase connection: paste the web app's firebaseConfig, or choose Use without an
account (see docs/running.md). scripts\web\serve.ps1 runs it the way it is hosted.

-Config emulators starts the local Firebase emulators too.

.EXAMPLE
.\scripts\web\run.ps1
.\scripts\web\run.ps1 -Browser edge
.\scripts\web\run.ps1 -Config emulators
#>
param(
    [ValidateSet('dev', 'emulators', 'prod')]
    [string] $Config = 'dev',

    # Browser to open. Default: Chrome when installed, else Edge.
    [ValidateSet('chrome', 'edge')]
    [string] $Browser,

    # Fixed port, so what the browser saves (an on-device library, the
    # connection) is kept between runs; each port is a separate site.
    [int] $Port = 5050
)

. "$PSScriptRoot\..\common.ps1"

$flutter = Find-Flutter
if (-not $Browser) {
    $chrome = Find-FirstPath @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    $Browser = if ($chrome) { 'chrome' } else { 'edge' }
}
if (Test-Port $Port) { Stop-WithError "Port $Port is in use. Use -Port to pick another." }

Install-AppDependencies
if ($Config -eq 'emulators') { Start-FirebaseEmulators $EmulatorProject }

Write-Step "Starting Capsula ($Config) in $Browser at http://localhost:$Port. Press q to quit."
Push-Location $RepoRoot
try {
    Invoke-Tool $flutter (@('run', '-d', $Browser, '--web-port', "$Port") + (Get-DartDefineArgs $Config))
} finally { Pop-Location }
