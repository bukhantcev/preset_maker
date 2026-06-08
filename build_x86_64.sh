#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -x ".venv_x86/bin/python" ]; then
  arch -x86_64 /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 -m venv .venv_x86
fi

arch -x86_64 .venv_x86/bin/python -m pip install --upgrade pip
arch -x86_64 .venv_x86/bin/python -m pip install -r requirements.txt -r requirements-build.txt
rm -rf build dist
arch -x86_64 .venv_x86/bin/pyinstaller --clean --noconfirm preset_maker.spec

mkdir -p release_preset_maker
rm -rf "release_preset_maker/GrandMA2 Passport-x86_64.app"
rm -f "release_preset_maker/GrandMA2 Passport-x86_64.zip"
cp -R "dist/GrandMA2 Passport.app" "release_preset_maker/GrandMA2 Passport-x86_64.app"
ditto -c -k --keepParent "release_preset_maker/GrandMA2 Passport-x86_64.app" "release_preset_maker/GrandMA2 Passport-x86_64.zip"

echo "Built release_preset_maker/GrandMA2 Passport-x86_64.zip"
