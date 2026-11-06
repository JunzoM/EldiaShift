#!/bin/bash
# Mac 版の App Store 用スクリーンショット（2560 × 1600・6枚）を、この Mac で撮る。
# 見本のデータ（保存しない・同期しない）で起動し、アプリが自分の窓を画像に書き出す（-demoSnapshot）ので、
# 画面収録の許可は要らない。
#
# 使い方（リポジトリのフォルダで）:
#   bash scripts/mac-screenshots.sh
# できた画像は shots/mac/ に入る（透過なしの PNG）。
set -euo pipefail
cd "$(dirname "$0")/.."

out=shots/mac
dd=$(mktemp -d)
mkdir -p "$out"

# 署名しない（その場で動かすだけ）。iCloud の権限は外す
cfg="$dd/adhoc.xcconfig"
cat > "$cfg" <<'EOF'
CODE_SIGN_IDENTITY = -
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM =
PROVISIONING_PROFILE_SPECIFIER =
CODE_SIGN_ENTITLEMENTS =
CODE_SIGN_ENTITLEMENTS[sdk=macosx*] =
EOF

echo "ビルド中…"
xcodebuild -project EldiaShift.xcodeproj -scheme EldiaShift \
  -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug \
  -derivedDataPath "$dd/build" -xcconfig "$cfg" build -quiet
app="$dd/build/Build/Products/Debug-maccatalyst/EldiaShift.app"

# 撮り終わったら、このビルドを Mac から忘れさせて消す
# （残すと、共有のリンクや TestFlight が、署名の無いこのビルドを開こうとする）
cleanup() {
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app" 2>/dev/null || true
  rm -rf "$dd"
}
trap cleanup EXIT

shoot() {  # ファイル名 起動オプション…
  name=$1; shift
  echo "撮影: $name"
  "$app/Contents/MacOS/EldiaShift" -demoLayout -demoAppStore -appearanceMode light \
    -AppleLanguages "(ja)" -AppleLocale ja_JP -demoSnapshot "$dd/$name.png" "$@" >/dev/null 2>&1
  # 窓の幅が 1 ポイント広いことがあるので、2560 × 1600 に切りそろえる。
  # App Store Connect は透明（アルファ）付きの画像を受け付けないため、JPEG を経由して取り除く
  sips --cropToHeightWidth 1600 2560 "$dd/$name.png" >/dev/null
  sips -s format jpeg -s formatOptions 100 "$dd/$name.png" --out "$dd/$name.jpg" >/dev/null
  sips -s format png "$dd/$name.jpg" --out "$out/$name.png" >/dev/null
}

shoot 1-home -demoHome
shoot 2-month
shoot 3-day -demoDay -demoEdit
shoot 4-print -demoTabPrint
shoot 5-stores -demoTabStores
shoot 6-staff -demoTabStaff

echo "できました: $out/"
