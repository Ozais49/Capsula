<#
.SYNOPSIS
Starts a release of one part of Capsula: sets its version, commits, and tags it.

.DESCRIPTION
Each part is released on its own, by a tag that starts its GitHub Actions release:

  app       app-v<version>       signed APK and App Bundle (GitHub release, testers)
  web       web-v<version>       Firebase Hosting
  api       api-v<version>       Docker image on GitHub Container Registry
  firebase  firebase-v<version>  Firestore rules and indexes

For app, web and api the version is written to that project's pubspec.yaml (the
workflow checks the tag matches). Firebase has no version file; the tag is enough.

Without -Push it only commits and tags locally, and shows the command to push.

.EXAMPLE
.\scripts\release.ps1 -Component app -Version 1.1.0
.\scripts\release.ps1 -Component web -Version 1.0.1 -Push
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('app', 'web', 'api', 'firebase')]
    [string] $Component,

    # Semantic version, e.g. 1.2.0.
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,

    # Push the commit and tag to origin, which starts the release.
    [switch] $Push
)

. "$PSScriptRoot\common.ps1"

$git = Find-OnPath 'git'
if (-not $git) { Stop-WithError 'git not found.' }
Push-Location $RepoRoot
try {
    if (& $git status --porcelain) {
        Stop-WithError 'There are uncommitted changes. Commit or stash them first.'
    }
    $tag = "$Component-v$Version"
    if (& $git tag --list $tag) { Stop-WithError "Tag $tag already exists." }

    $pubspec = switch ($Component) {
        'app' { Join-Path $AppDir 'pubspec.yaml' }
        'web' { Join-Path $WebDir 'pubspec.yaml' }
        'api' { Join-Path $ApiDir 'pubspec.yaml' }
        default { $null }
    }
    if ($pubspec) {
        $text = [IO.File]::ReadAllText($pubspec)
        $current = [regex]::Match($text, '(?m)^version:\s*(\S+)').Groups[1].Value
        # The app keeps a build number after '+'; the release build uses
        # the workflow's run number, so it's only bumped for local builds.
        $new = $Version
        if ($current -match '\+(\d+)$') { $new = "$Version+$([int]$Matches[1] + 1)" }
        $text = [regex]::Replace($text, '(?m)^version:\s*\S+', "version: $new")
        [IO.File]::WriteAllText($pubspec, $text)
        Write-Step "$Component version $current -> $new"
        Invoke-Tool $git @('add', $pubspec)
        Invoke-Tool $git @('commit', '-m', "Release $Component $Version")
    }
    Invoke-Tool $git @('tag', '-a', $tag, '-m', "Release $Component $Version")
    Write-Step "Tagged $tag"

    if ($Push) {
        $branch = (& $git rev-parse --abbrev-ref HEAD).Trim()
        Invoke-Tool $git @('push', 'origin', $branch)
        Invoke-Tool $git @('push', 'origin', $tag)
        Write-Host "Pushed. Follow the release under Actions on GitHub." -ForegroundColor Green
    } else {
        Write-Host "To start the release: git push origin HEAD; git push origin $tag"
    }
} finally {
    Pop-Location
}
