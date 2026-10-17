<#
.SYNOPSIS
Builds the web app for release and serves it locally, the way Firebase Hosting does.

.DESCRIPTION
Builds build\web, then serves it with the Firebase Hosting emulator at
http://localhost:5000 (stop it with Ctrl+C). Like the hosted site, it provides the
project's Firebase settings, so the app connects without asking. That needs you to be
signed in to the Firebase CLI with access to the project (`firebase login`); otherwise
the app asks for the connection, as when running with run.ps1.

Use this to check a build before deploying it (see docs/hosting.md).

.EXAMPLE
.\scripts\web\serve.ps1
.\scripts\web\serve.ps1 -SkipBuild
#>
param(
    [ValidateSet('prod', 'dev')]
    [string] $Config = 'prod',

    # Serve the last build instead of building again.
    [switch] $SkipBuild,

    # Firebase project whose settings the local site provides.
    [string] $Project = 'capsula-ygtech'
)

. "$PSScriptRoot\..\common.ps1"

if (Test-Port 5000) { Stop-WithError 'Port 5000 is in use (is it already being served?).' }

if (-not $SkipBuild) {
    Install-AppDependencies
    Write-Step "Building the web app ($Config)"
    Push-Location $RepoRoot
    try {
        Invoke-Tool (Find-Flutter) (@('build', 'web', '--release') + (Get-DartDefineArgs $Config))
    } finally { Pop-Location }
}
if (-not (Test-Path (Join-Path $RepoRoot 'build\web\index.html'))) {
    Stop-WithError 'No build in build\web. Run without -SkipBuild.'
}

Write-Step 'Serving build\web at http://localhost:5000. Press Ctrl+C to stop.'
Push-Location $RepoRoot
try {
    Invoke-Firebase @('emulators:start', '--only', 'hosting', '--project', $Project)
} finally { Pop-Location }
