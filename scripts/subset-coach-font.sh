#!/bin/sh
# コーチマークの説明文を変えたら実行する（手書き風の文字を、説明に使う文字だけに絞り直す）
# 必要なもの：pip install fonttools ／ Klee One SemiBold（https://github.com/google/fonts/tree/main/ofl/kleeone）
set -e
cd "$(dirname "$0")/.."
SRC=${1:-KleeOne-SemiBold.ttf}
python3 - <<'PY' > /tmp/coach-chars.txt
import re
s = open("EldiaShift/CoachMarks.swift", encoding="utf-8").read()
chars = set("".join(re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', s)))
chars |= set("0123456789０１２３４５６７８９ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz・、。「」（）()→〜…ー：:？！ 　-")
print("".join(sorted(chars)), end="")
PY
pyftsubset "$SRC" --text-file=/tmp/coach-chars.txt --output-file=EldiaShift/Fonts/CoachHand.ttf \
  --no-hinting --drop-tables+=DSIG,BASE,vhea,vmtx,VORG
ls -la EldiaShift/Fonts/CoachHand.ttf
