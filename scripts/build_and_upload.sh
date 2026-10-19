#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="FootballGPS"
ARCHIVE_PATH="$PROJECT_DIR/build/FootballGPS.xcarchive"
EXPORT_PATH="$PROJECT_DIR/build/export"
EXPORT_OPTIONS="$PROJECT_DIR/scripts/ExportOptions.plist"

API_KEY_ID="J5CCA4HSGM"
API_ISSUER_ID="12bba605-a18c-4c38-b996-eddc1fcef408"
API_KEY_PATH="$HOME/private_keys/AuthKey_${API_KEY_ID}.p8"

if [ ! -f "$API_KEY_PATH" ]; then
  echo "APIキーが見つかりません: $API_KEY_PATH" >&2
  exit 1
fi

echo "==> Build番号を全ターゲット一括インクリメント"
xcrun agvtool next-version -all

echo "==> アーカイブ作成 (scheme: $SCHEME)"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -project "$PROJECT_DIR/FootballGPS.xcodeproj" \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=iOS'

echo "==> エクスポート & App Store Connectへアップロード"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID" \
  -allowProvisioningUpdates

echo "==> 完了。TestFlightでの処理を待ってください(通常数分〜数十分)"
