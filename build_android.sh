#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/android_app"

export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
./gradlew assembleDebug

cd ..
mkdir -p release_preset_maker
rm -f "release_preset_maker/GrandMA2 Passport.apk"
rm -f "release_preset_maker/GrandMA2 Passport-android-debug.apk"
cp android_app/app/build/outputs/apk/debug/app-debug.apk "release_preset_maker/Passport creator-android-debug.apk"

echo "Built release_preset_maker/Passport creator-android-debug.apk"
