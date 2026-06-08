#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

bash ./build_arm64.sh
bash ./build_x86_64.sh

echo "Built macOS arm64 and x86_64 apps in release_preset_maker/"
