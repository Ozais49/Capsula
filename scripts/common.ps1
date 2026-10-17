# Shared helpers for the run scripts. Dot-source it: . "$PSScriptRoot\..\common.ps1"
# Works in Windows PowerShell 5.1 and PowerShell 7.

$ErrorActionPreference = 'Stop'

# Repository root (the folder with pubspec.yaml), whatever folder the script
# was started from. This file lives in scripts\.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$AppId = 'com.ygtech.capsula'

# Project the local emulators run as. The app (dev config) and the API use the
# same one, so they all see the same local data.
$EmulatorProject = 'capsula-ygtech'

function Write-Step([string] $Text) {
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Stop-WithError([string] $Text) {
    Write-Host "ERROR: $Text" -ForegroundColor Red
    exit 1
}

# Runs a program and stops the script if it fails.
function Invoke-Tool {
    param([string] $Exe, [string[]] $Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        Stop-WithError "$([IO.Path]::GetFileName($Exe)) $($Arguments -join ' ') failed (exit code $LASTEXITCODE)"
    }
}

# The first of $Candidates that exists, or $null.
function Find-FirstPath([string[]] $Candidates) {
    foreach ($c in $Candidates) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    return $null
}

# A Windows program (.exe/.bat/.cmd) on PATH. Skips extensionless shell
# scripts, which PowerShell can't run.
function Find-OnPath([string] $Name) {
    foreach ($ext in @('.exe', '.bat', '.cmd')) {
        $cmd = Get-Command "$Name$ext" -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Find-Flutter {
    $found = Find-OnPath 'flutter'
    if (-not $found) {
        $found = Find-FirstPath @(
            $(if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat' }),
            'C:\src\flutter\bin\flutter.bat',
            (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat')
        )
    }
    if (-not $found) {
        Stop-WithError 'Flutter not found. Install it (see docs/setup.md) or set FLUTTER_ROOT.'
    }
    return $found
}

# Dart from the same Flutter install, so versions match.
function Find-Dart {
    $flutterBin = Split-Path (Find-Flutter)
    $found = Find-FirstPath @((Join-Path $flutterBin 'dart.bat'))
    if (-not $found) { $found = Find-OnPath 'dart' }
    if (-not $found) { Stop-WithError 'Dart not found. It comes with Flutter (see docs/setup.md).' }
    return $found
}

function Find-Adb {
    $sdk = $env:ANDROID_HOME
    if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
    if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
    $found = Find-FirstPath @((Join-Path $sdk 'platform-tools\adb.exe'))
    if (-not $found) { $found = Find-OnPath 'adb' }
    if (-not $found) {
        Stop-WithError 'adb not found. Install the Android SDK platform tools (see docs/setup.md).'
    }
    return $found
}

# The Firebase CLI as (program, leading arguments): the installed `firebase`,
# or `npx firebase-tools` when only Node.js is installed.
function Find-Firebase {
    $found = Find-OnPath 'firebase'
    if ($found) { return @($found) }
    $npx = Find-OnPath 'npx'
    if ($npx) {
        Write-Host 'Firebase CLI not installed; using it through npx (downloads it once).'
        return @($npx, '--yes', 'firebase-tools@13')
    }
    Stop-WithError 'The Firebase CLI needs Node.js. Install Node.js, then run: npm install -g firebase-tools'
}

function Invoke-Firebase([string[]] $Arguments) {
    $fb = @(Find-Firebase)
    $exe = $fb[0]
    $rest = @()
    if ($fb.Count -gt 1) { $rest = $fb[1..($fb.Count - 1)] }
    Invoke-Tool $exe ($rest + $Arguments)
}

function Assert-Java {
    if (-not (Find-OnPath 'java')) {
        Stop-WithError 'The Firebase emulators need Java 11 or newer. Install a JDK and add it to PATH.'
    }
}

# Whether something is listening on localhost:$Port.
function Test-Port([int] $Port) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        return $task.Wait(500) -and $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Wait-ForPort([int] $Port, [int] $Seconds, [string] $What) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Port $Port) { return }
        Start-Sleep -Milliseconds 500
    }
    Stop-WithError "$What did not start on port $Port within $Seconds seconds."
}

# Starts the Firebase Auth and Firestore emulators in their own window,
# unless they're already running.
function Start-FirebaseEmulators([string] $Project) {
    if ((Test-Port 8080) -and (Test-Port 9099)) {
        Write-Step 'Firebase emulators already running'
        return
    }
    Assert-Java
    Write-Step "Starting Firebase emulators (project $Project) in a new window"
    $fb = @(Find-Firebase)
    $fbArgs = @()
    if ($fb.Count -gt 1) { $fbArgs = $fb[1..($fb.Count - 1)] }
    $fbArgs += @('emulators:start', '--only', 'auth,firestore', '--project', $Project)
    $quoted = ($fbArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    Start-Process -FilePath 'cmd.exe' -WorkingDirectory $RepoRoot `
        -ArgumentList '/k', "title Firebase emulators && `"$($fb[0])`" $quoted"
    Wait-ForPort 8080 90 'The Firestore emulator'
    Wait-ForPort 9099 30 'The Auth emulator'
    Write-Host 'Emulator UI: http://localhost:4000'
}

# `flutter pub get` for the app (and the shared package it uses).
function Install-AppDependencies {
    Write-Step 'Getting app dependencies'
    Push-Location $RepoRoot
    try { Invoke-Tool (Find-Flutter) @('pub', 'get') } finally { Pop-Location }
}

# The config file for an environment: config/<env>.json.
function Get-ConfigFile([string] $Name) {
    $file = Join-Path $RepoRoot "config\$Name.json"
    if (-not (Test-Path $file)) { Stop-WithError "No config file $file" }
    return $file
}

# Picks the Android phone to use: $Requested, the only one connected, or one
# the user chooses. Explains unauthorized or offline phones.
function Select-AndroidDevice([string] $Requested) {
    $adb = Find-Adb
    & $adb start-server | Out-Null
    $lines = & $adb devices -l | Select-Object -Skip 1 | Where-Object { $_.Trim() }
    $devices = @()
    foreach ($line in $lines) {
        $parts = $line -split '\s+'
        $model = ($parts | Where-Object { $_ -like 'model:*' }) -replace '^model:', ''
        $devices += [pscustomobject]@{ Serial = $parts[0]; State = $parts[1]; Model = $model }
    }

    foreach ($d in $devices | Where-Object { $_.State -ne 'device' }) {
        switch ($d.State) {
            'unauthorized' { Write-Host "$($d.Serial): unlock the phone and accept 'Allow USB debugging'." -ForegroundColor Yellow }
            'offline' { Write-Host "$($d.Serial): offline. Unplug and reconnect the cable." -ForegroundColor Yellow }
            default { Write-Host "$($d.Serial): $($d.State)" -ForegroundColor Yellow }
        }
    }
    $ready = @($devices | Where-Object { $_.State -eq 'device' })

    if ($Requested) {
        if (-not ($ready | Where-Object { $_.Serial -eq $Requested })) {
            Stop-WithError "Phone $Requested is not connected and ready."
        }
        return $Requested
    }
    if ($ready.Count -eq 0) {
        Stop-WithError ('No phone found. Connect it by USB with USB debugging on ' +
            '(Settings > Developer options), then try again. See docs/setup.md.')
    }
    if ($ready.Count -eq 1) {
        Write-Step "Using $($ready[0].Model) ($($ready[0].Serial))"
        return $ready[0].Serial
    }
    Write-Host 'Several phones are connected:'
    for ($i = 0; $i -lt $ready.Count; $i++) {
        Write-Host "  [$($i + 1)] $($ready[$i].Model) ($($ready[$i].Serial))"
    }
    $choice = Read-Host 'Which one? (number)'
    $index = 0
    if (-not [int]::TryParse($choice, [ref] $index) -or $index -lt 1 -or $index -gt $ready.Count) {
        Stop-WithError 'No phone chosen.'
    }
    return $ready[$index - 1].Serial
}

# Lets the phone reach services on this computer at localhost, over USB:
# the Firebase emulators and the API server.
function Connect-PhoneToComputer([string] $Serial, [int[]] $Ports) {
    $adb = Find-Adb
    foreach ($p in $Ports) {
        Invoke-Tool $adb @('-s', $Serial, 'reverse', "tcp:$p", "tcp:$p") | Out-Null
    }
    Write-Host "Phone's localhost ports $($Ports -join ', ') now reach this computer."
}

# --dart-define-from-file arguments for a config. The emulators config only
# switches to the emulators, so it is layered over dev, which names the project.
function Get-DartDefineArgs([string] $Name) {
    if ($Name -eq 'emulators') {
        return @(
            "--dart-define-from-file=$(Get-ConfigFile 'dev')",
            "--dart-define-from-file=$(Get-ConfigFile 'emulators')"
        )
    }
    return @("--dart-define-from-file=$(Get-ConfigFile $Name)")
}
