<#
.SYNOPSIS
Builds a release APK, installs it on a connected Android phone and opens it.

.DESCRIPTION
The installed app stays on the phone and works without the computer. Run it again to
update the app; data on the phone is kept.

If Android refuses the update because the installed copy was signed with a different
key (for example a debug build), use -Clean to uninstall it first. That deletes a
library kept on the phone without an account, so export it first.

.EXAMPLE
.\scripts\phone\install.ps1
.\scripts\phone\install.ps1 -SkipBuild
.\scripts\phone\install.ps1 -Clean
#>
param(
    # Which config/<env>.json to build with.
    [ValidateSet('prod', 'dev')]
    [string] $Config = 'prod',

    # Phone serial (from `adb devices`). Optional when one phone is connected.
    [string] $Device,

    # Install the APK built last time instead of building again.
    [switch] $SkipBuild,

    # Uninstall the app first (deletes its data on the phone).
    [switch] $Clean
)

. "$PSScriptRoot\..\common.ps1"

$adb = Find-Adb
$serial = Select-AndroidDevice $Device
$apk = Join-Path $AppDir 'build\app\outputs\flutter-apk\app-release.apk'

if (-not $SkipBuild) {
    Install-AppDependencies
    Write-Step "Building the release APK ($Config)"
    Push-Location $AppDir
    try {
        Invoke-Tool (Find-Flutter) (@('build', 'apk', '--release') + (Get-DartDefineArgs $Config))
    } finally { Pop-Location }
}
if (-not (Test-Path $apk)) { Stop-WithError "No APK at $apk. Run without -SkipBuild." }

if ($Clean) {
    Write-Step 'Uninstalling the current app'
    & $adb -s $serial uninstall $AppId | Out-Host
}

Write-Step 'Installing on the phone'
$output = & $adb -s $serial install -r $apk 2>&1 | Out-String
Write-Host $output.Trim()
if ($output -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
    Stop-WithError ('The installed app was signed with a different key. Run again with -Clean ' +
        '(this deletes data kept on the phone without an account; export it first).')
}
if ($LASTEXITCODE -ne 0 -or $output -notmatch 'Success') { Stop-WithError 'Install failed.' }

Write-Step 'Opening Capsula'
Invoke-Tool $adb @('-s', $serial, 'shell', 'monkey', '-p', $AppId, '-c',
    'android.intent.category.LAUNCHER', '1') | Out-Null
Write-Host 'Done. Capsula is installed and open on the phone.' -ForegroundColor Green
