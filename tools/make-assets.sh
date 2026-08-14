#!/bin/sh
# 重新產生 README 的示意圖（assets/demo.svg、assets/demo-zh.svg）。
#
# ⚠️ 這個目錄只是「產生文件用的工具」，plugin 本身跑起來完全不需要它。
# 它要 python3；plugin 不要。改了 renderer 之後跑一次，圖就跟著更新。
#
# 圖不是截圖，是把 list.awk / md.awk 的真實輸出轉成 SVG ——
# 比截圖精確（每個字都在它該在的格子上），而且進得了版控、diff 看得懂。
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

for lang in en zh; do
    LC_ALL=C awk -v q= -v cur=2 -v w=46 -v h=38 -v total=8 -v scope=session \
        -v lang="$lang" -v mf=/dev/null \
        -f "$ROOT/scripts/width.awk" -f "$ROOT/scripts/list.awk" \
        "$DIR/items.tsv" > "$T/left.$lang"
done

# id 要跟左邊選中的那一列一致（items.tsv 第 2 列 @355，狀態 running）——
# 圖的重點就是「選中的那則在跑，所以下半部照出它的畫面」。
{ printf '\033[2m@355\033[0m\n\n'
  LC_ALL=C awk -v w=80 \
      -f "$ROOT/scripts/width.awk" -f "$ROOT/scripts/graph.awk" \
      -f "$ROOT/scripts/seq.awk"   -f "$ROOT/scripts/flow.awk" \
      -f "$ROOT/scripts/md.awk" "$DIR/body.md" \
    | awk 'NR == 1 && $0 == "" { next } { print }'
} > "$T/right"

# 第三個參數是鏡像區。mirror.ansi 是 `tmux capture-pane -e` 從一個**真的**
# 派工出去的 agent 抓下來的畫面（已經拿掉那行含花費與額度的用量統計）。
# 存成固定素材而不是每次現抓 —— 不然重產這張圖就得先派一個 agent 出去。
for lang in en zh; do
    python3 "$DIR/compose.py" "$T/left.$lang" "$T/right" "$DIR/mirror.ansi" \
        > "$T/frame.$lang"
done
python3 "$DIR/ansi2svg.py" < "$T/frame.en" > "$ROOT/assets/demo.svg"
python3 "$DIR/ansi2svg.py" < "$T/frame.zh" > "$ROOT/assets/demo-zh.svg"
printf 'assets/demo.svg\nassets/demo-zh.svg\n'
