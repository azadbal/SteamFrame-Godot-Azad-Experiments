param([switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $env:USERPROFILE 'Documents\_apps\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { throw 'Run python tools/setup_godot.py first.' }
& $godot --headless --xr-mode off --path $projectDir --editor --import
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
if (-not $SkipTests) {
    & $godot --headless --xr-mode off --path $projectDir -- --self-test
    if ($LASTEXITCODE -ne 0) { throw 'Demo self-tests failed.' }
}
New-Item -ItemType Directory -Force (Join-Path $projectDir 'build') | Out-Null
& $godot --headless --xr-mode off --path $projectDir --export-release 'Steam Frame ARM64' (Join-Path $projectDir 'build\frame-lab.arm64')
if ($LASTEXITCODE -ne 0) { throw 'Godot export failed.' }
Copy-Item -LiteralPath (Join-Path $projectDir 'vrpreferences.json') -Destination (Join-Path $projectDir 'build\vrpreferences.json')
