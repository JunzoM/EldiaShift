#!/bin/bash
# iPhone Duo（折りたたみ）の App Store 用スクリーンショットを、この Mac のシミュレーターで撮る。
# GitHub の環境にはまだ Duo のシミュレーターが無いため、Xcode 27 の入った Mac で動かす。
#
# 使い方（リポジトリのフォルダで）:
#   bash scripts/duo-screenshots.sh
# 開いた画面 → 閉じた画面 の順に4枚ずつ撮る。途中で、シミュレーターを閉じた状態にするよう案内が出る。
# できた画像は shots/duo/ に入る（透過なしの PNG）。
set -euo pipefail
cd "$(dirname "$0")/.."

bid=com.bestdelight.eldiashift
out=shots/duo
mkdir -p "$out"

# Duo のシミュレーターを探す（無ければ Xcode › Settings › Components で iOS 27 を入れる）
dev=$(xcrun simctl list devices available | grep -i "Duo" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [ -z "$dev" ]; then
  echo "iPhone Duo のシミュレーターが見つかりません。Xcode › Window › Devices and Simulators で追加してください。"
  exit 1
fi
echo "使う端末: $(xcrun simctl list devices available | grep "$dev" | sed -E 's/^ *//')"

echo "ビルド中…"
xcodebuild -project EldiaShift.xcodeproj -scheme EldiaShift \
  -destination "id=$dev" -configuration Debug -derivedDataPath build/duo \
  CODE_SIGNING_ALLOWED=NO build -quiet
app=build/duo/Build/Products/Debug-iphonesimulator/EldiaShift.app

xcrun simctl boot "$dev" 2>/dev/null || true
# Simulator を開く。Xcode の版や入れ直しで置き場所が変わるため、順に探す
open_simulator() {
  local p
  for p in "$(xcode-select -p)/Applications/Simulator.app" \
           "$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.iphonesimulator'" 2>/dev/null | head -1)"; do
    [ -n "$p" ] && [ -d "$p" ] && open "$p" && return 0
  done
  open -b com.apple.iphonesimulator 2>/dev/null && return 0
  open -a Simulator 2>/dev/null && return 0
  echo "Simulator を開けませんでした。Xcode のメニュー › Open Developer Tool › Simulator で開いてから Enter を押してください。"
  read -r _
}
open_simulator
xcrun simctl bootstatus "$dev" -b
xcrun simctl status_bar "$dev" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularMode active --cellularBars 4 || true
xcrun simctl install "$dev" "$app"

shoot() {  # 画面（primary=閉じた外側 / primary-1=開いた内側） ファイル名 起動オプション…
  disp=$1; name=$2; shift 2
  xcrun simctl terminate "$dev" $bid >/dev/null 2>&1 || true
  xcrun simctl launch "$dev" $bid -demoLayout -demoAppStore -AppleLanguages "(ja)" -AppleLocale ja_JP "$@" >/dev/null
  sleep 12
  # Duo は画面が2枚あるので、撮る画面を指定する（指定しないと外側だけを撮り、開いた状態では真っ黒になる）
  xcrun simctl io "$dev" screenshot --display="$disp" --mask=ignored "$out/tmp.png" >/dev/null
  # 透過をなくす（App Store は透過のある画像を受け付けない）
  sips -s format jpeg "$out/tmp.png" --out "$out/tmp.jpg" >/dev/null
  sips -s format png "$out/tmp.jpg" --out "$out/$name.png" >/dev/null
  # 横向きで撮る画面なのに縦長に保存されたら、横に回す（逆さまなら ROTATE=270 を付けて実行）
  if [ "${LANDSCAPE:-0}" = 1 ]; then
    w=$(sips -g pixelWidth "$out/$name.png" | awk 'END{print $2}')
    h=$(sips -g pixelHeight "$out/$name.png" | awk 'END{print $2}')
    [ "$w" -lt "$h" ] && sips -r "${ROTATE:-90}" "$out/$name.png" >/dev/null
  fi
  rm -f "$out/tmp.png" "$out/tmp.jpg"
  echo "  $name.png  $(sips -g pixelWidth -g pixelHeight "$out/$name.png" | tail -2 | awk '{print $2}' | paste -sd'x' -)"
}

set4() {  # 画面 接頭辞
  shoot "$1" "$2-1-home" -demoHome
  shoot "$1" "$2-2-month"
  shoot "$1" "$2-3-day" -demoDay -demoEdit
  shoot "$1" "$2-4-print" -demoTabPrint
}

# 開いた画面は、縦向きだとシミュレーターの画面を取り出せず真っ黒になるため、横向きで撮る（App Store は 2853x2007 の横向きも受け付ける）
read -r -p "シミュレーターを「開いた状態」の「横向き」にして、Enter を押してください… " _
LANDSCAPE=1 set4 primary-1 inner
read -r -p "シミュレーターを「閉じた状態」の「縦向き」にして、Enter を押してください… " _
set4 primary outer

echo
echo "できあがり: $out/"
echo "App Store の大きさ: 開いた画面 2853x2007（横） ／ 閉じた画面 1398x2034（縦）。違っていたら教えてください。"
open "$out"
