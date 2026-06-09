$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

if (!(Test-Path ".venv_win\\Scripts\\python.exe")) {
    py -3.12 -m venv .venv_win
}

.\\.venv_win\\Scripts\\python.exe -m pip install --upgrade pip
.\\.venv_win\\Scripts\\python.exe -m pip install -r requirements.txt -r requirements-build.txt

if (Test-Path "build") { Remove-Item -Recurse -Force "build" }
if (Test-Path "dist") { Remove-Item -Recurse -Force "dist" }

.\\.venv_win\\Scripts\\pyinstaller.exe --clean --noconfirm preset_maker_windows.spec

New-Item -ItemType Directory -Force -Path "release_preset_maker" | Out-Null
$exe = "dist\\Passport creator.exe"
$releaseExe = "release_preset_maker\\Passport creator-windows.exe"
$releaseZip = "release_preset_maker\\Passport creator-windows.zip"
$oldReleaseExe = "release_preset_maker\\GrandMA2 Passport-windows.exe"
$oldReleaseZip = "release_preset_maker\\GrandMA2 Passport-windows.zip"

if (!(Test-Path $exe)) {
    throw "PyInstaller finished, but $exe was not created"
}

if (Test-Path $releaseExe) { Remove-Item -Force $releaseExe }
if (Test-Path $releaseZip) { Remove-Item -Force $releaseZip }
if (Test-Path $oldReleaseExe) { Remove-Item -Force $oldReleaseExe }
if (Test-Path $oldReleaseZip) { Remove-Item -Force $oldReleaseZip }

Copy-Item $exe $releaseExe -Force
Compress-Archive -Path $releaseExe -DestinationPath $releaseZip -Force

Write-Host "Built $releaseZip"
