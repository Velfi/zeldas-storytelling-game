[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [switch]$SkipBuild,
    [string]$EngineRoot = (Join-Path $PSScriptRoot "..\..\zelda-engine")
)

$ErrorActionPreference = "Stop"
if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
    throw "Version must be MAJOR.MINOR.PATCH with an optional prerelease suffix"
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$build = Join-Path $root "build"
$exe = Join-Path $build "zeldas-storytelling-game.exe"
if (-not $SkipBuild) { & "$PSScriptRoot\build_windows.ps1" -EngineRoot $EngineRoot }
if (-not (Test-Path $exe)) { throw "Missing executable: $exe" }

$stage = Join-Path $build "windows-release"
$archive = Join-Path $build "zeldas-storytelling-game-v$Version-windows-x86_64.zip"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $archive) { Remove-Item $archive -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item $exe $stage
Get-ChildItem (Join-Path $build "*.dll") | Copy-Item -Destination $stage
Copy-Item (Join-Path $root "assets") $stage -Recurse
Copy-Item (Join-Path $build "shaders") $stage -Recurse
Copy-Item (Join-Path $root "README.md") $stage

Compress-Archive -Path "$stage\*" -DestinationPath $archive -CompressionLevel Optimal
Write-Host "Packaged $archive"
