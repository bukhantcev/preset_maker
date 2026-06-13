#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/web_app/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Не найден $ENV_FILE" >&2
  exit 1
fi

read_env() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | sed -E "s/^${key}=//; s/^['\"]//; s/['\"]$//"
}

export YANDEX_CLIENT_ID="$(read_env YANDEX_CLIENT_ID)"
export YANDEX_CLIENT_SECRET="$(read_env YANDEX_CLIENT_SECRET)"

if [[ -z "${YANDEX_CLIENT_ID}" || -z "${YANDEX_CLIENT_SECRET}" ]]; then
  echo "В $ENV_FILE нет YANDEX_CLIENT_ID/YANDEX_CLIENT_SECRET" >&2
  exit 1
fi

TMP_XCCONFIG="$(mktemp "${TMPDIR:-/tmp}/passportcreator.XXXXXX.xcconfig")"
trap 'rm -f "$TMP_XCCONFIG"' EXIT
{
  printf 'YANDEX_CLIENT_ID = %s\n' "$YANDEX_CLIENT_ID"
  printf 'YANDEX_CLIENT_SECRET = %s\n' "$YANDEX_CLIENT_SECRET"
} > "$TMP_XCCONFIG"

cd "$ROOT_DIR/ios_app/GrandMA2Passport"
xcodebuild \
  -project GrandMA2Passport.xcodeproj \
  -scheme "GrandMA2 Passport" \
  -configuration Debug \
  -xcconfig "$TMP_XCCONFIG" \
  "$@"
