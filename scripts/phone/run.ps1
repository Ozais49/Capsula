<#
.SYNOPSIS
Runs Capsula on a connected Android phone, with hot reload.

.DESCRIPTION
Finds the phone, gets dependencies and starts the app from source. While it runs,
press r to hot reload, R to hot restart and q to quit.

With -Config emulators it also starts the local Firebase emulators and connects the
phone to them (and to a local API server) over the USB cable.

.EXAMPLE
.\scripts\phone\run.ps1
.\scripts\phone\run.ps1 -Config emulators
.\scripts\phone\run.ps1 -Release
.\scripts\phone\run.ps1 -Device R58M123ABC
#>
param(
    # Which config/<env>.json to build with.
    [ValidateSet('dev', 'emulators', 'prod')]
    [string] $Config = 'dev',

    # Phone serial (from `adb devices`). Optional when one phone is connected.
    [string] $Device,

    # Release mode: as fast as the installed app, but no hot reload.
    [switch] $Release
)

. "$PSScriptRoot\..\common.ps1"

$flutter = Find-Flutter
$serial = Select-AndroidDevice $Device
Install-AppDependencies

if ($Config -eq 'emulators') {
    Start-FirebaseEmulators $EmulatorProject
    # config/emulators.json points the app at localhost; these make the
    # phone's localhost the computer: Firestore, Auth, API server.
    Connect-PhoneToComputer $serial @(8080, 9099, 8787)
}

$flutterArgs = @('run', '-d', $serial) + (Get-DartDefineArgs $Config)
if ($Release) { $flutterArgs += '--release' }

Write-Step "Starting Capsula ($Config) on the phone. Press q to quit."
Push-Location $RepoRoot
try { Invoke-Tool $flutter $flutterArgs } finally { Pop-Location }
