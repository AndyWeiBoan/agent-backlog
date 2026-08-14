#!/bin/sh
# 重新產生 README 的示意圖。
#
# ⚠️ 這個目錄只是「產生文件用的工具」，plugin 本身跑起來完全不需要它。
# 它要 python3；plugin 不要。改了 renderer 之後跑一次，圖就跟著更新。
#
# 圖不是截圖，是把 list.awk / md.awk 的真實輸出轉成 SVG ——
# 比截圖精確（每個字都在它該在的格子上），而且進得了版控、diff 看得懂。
#
# 產四張，兩種語言各兩種狀態：
#   demo.svg          選中一則還沒派工的 -> 整頁都是預覽
#   demo-running.svg  選中一則正在跑的   -> 下半部切出來照 agent 的畫面
# 兩張的差別只有「選中哪一列」和「有沒有第三個參數」，其餘完全相同 ——
# 這樣讀者對照兩張圖就看得出那一格是什麼時候冒出來的。
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

md() {   # $1 = 那則的 window_id（印在預覽第一行，跟左邊選中的列一致）
    printf '\033[2m%s\033[0m\n\n' "$1"
    LC_ALL=C awk -v w=80 \
        -f "$ROOT/scripts/width.awk" -f "$ROOT/scripts/graph.awk" \
        -f "$ROOT/scripts/seq.awk"   -f "$ROOT/scripts/flow.awk" \
        -f "$ROOT/scripts/md.awk" "$DIR/body.md" \
      | awk 'NR == 1 && $0 == "" { next } { print }'
}

list() { # $1 = 語言  $2 = 選中第幾列
    # ⚠️ 最後補白把提示列推到底。
    # list.awk 是用游標定位（\033[38;1H）把提示列釘在窗格最後一列的，
    # 但 ansi2svg 只認顏色碼，其他逃逸碼一律吃掉 —— 不補的話提示列會黏在
    # 清單正下方，跟真的畫面對不起來。這是產圖工具的責任，不該去動 renderer。
    LC_ALL=C awk -v q= -v cur="$2" -v w=46 -v h=38 -v total=8 -v scope=session \
        -v lang="$1" -v mf=/dev/null \
        -f "$ROOT/scripts/width.awk" -f "$ROOT/scripts/list.awk" \
        "$DIR/items.tsv" \
    | awk -v H=38 '{ a[NR] = $0 }
        END { for (i = 1; i < NR; i++) print a[i]
              for (i = NR; i < H; i++) print ""
              print a[NR] }'
}

# 未派工：items.tsv 第 3 列是 @339（pending）。沒有第三個參數 = 不切鏡像。
md @339 > "$T/right.idle"
for lang in en zh; do
    list "$lang" 3 > "$T/left.$lang.idle"
done

# 已派工：第 2 列是 @355（running）。
#
# 第三個參數是鏡像區。mirror.ansi 是 `tmux capture-pane -e` 從一個**真的**
# 派工出去、正在拆解這份 codebase 的 agent 抓下來的畫面
# （已經拿掉那行含花費與額度的用量統計，也挑了不含測試路徑的段落）。
# 存成固定素材而不是每次現抓 —— 不然重產這張圖就得先派一個 agent 出去。
md @355 > "$T/right.run"
for lang in en zh; do
    list "$lang" 2 > "$T/left.$lang.run"
done

for lang in en zh; do
    python3 "$DIR/compose.py" "$T/left.$lang.idle" "$T/right.idle" > "$T/f.$lang.idle"
    python3 "$DIR/compose.py" "$T/left.$lang.run"  "$T/right.run" \
        "$DIR/mirror.ansi" > "$T/f.$lang.run"
done

python3 "$DIR/ansi2svg.py" < "$T/f.en.idle" > "$ROOT/assets/demo.svg"
python3 "$DIR/ansi2svg.py" < "$T/f.zh.idle" > "$ROOT/assets/demo-zh.svg"
python3 "$DIR/ansi2svg.py" < "$T/f.en.run"  > "$ROOT/assets/demo-running.svg"
python3 "$DIR/ansi2svg.py" < "$T/f.zh.run"  > "$ROOT/assets/demo-running-zh.svg"
printf 'assets/demo.svg\nassets/demo-zh.svg\nassets/demo-running.svg\nassets/demo-running-zh.svg\n'
