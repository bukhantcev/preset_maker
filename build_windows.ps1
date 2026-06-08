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
Copy-Item "dist\\GrandMA2 Passport.exe" "release_preset_maker\\GrandMA2 Passport-windows.exe" -Force

Compress-Archive -Path "release_preset_maker\\GrandMA2 Passport-windows.exe" -DestinationPath "release_preset_maker\\GrandMA2 Passport-windows.zip" -Force

Write-Host "Built release_preset_maker\\GrandMA2 Passport-windows.zip"
