#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

arch -arm64 .venv/bin/python -m pip install -r requirements.txt -r requirements-build.txt
rm -rf build dist
arch -arm64 .venv/bin/pyinstaller --clean --noconfirm preset_maker.spec

mkdir -p release_preset_maker
rm -rf "release_preset_maker/GrandMA2 Passport-arm64.app"
rm -f "release_preset_maker/GrandMA2 Passport-arm64.zip"
cp -R "dist/GrandMA2 Passport.app" "release_preset_maker/GrandMA2 Passport-arm64.app"
ditto -c -k --keepParent "release_preset_maker/GrandMA2 Passport-arm64.app" "release_preset_maker/GrandMA2 Passport-arm64.zip"

echo "Built release_preset_maker/GrandMA2 Passport-arm64.zip"
