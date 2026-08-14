#!/bin/sh
# 鏡像窗格：把選中那則的畫面即時映到預覽下半部，用來看派出去的 agent 在幹嘛。
#
# 用法：mirror.sh <chooser 的 window_id>
# 要鏡像誰不是用參數傳的，是從那個 window 的 @agent_backlog_mirror 讀 ——
# chooser 換選項時改那個 option 就好，不用殺掉重開這一格（重開會閃）。
#
# ⚠️ tmux 沒有「同一個 pane 同時顯示在兩個地方」這種東西，所以只能 capture。
# capture-pane 拿到的是那一格**已經排版好的格線**，不會為了這裡的寬度重排 ——
# 來源比這裡寬的話右邊就是會被切掉。實測 Claude Code 沒問題（內容靠左，
# 切掉的是邊框與空白），但左右分割的 TUI（nvim + 檔案樹）會被切得沒法看。
#
# ⚠️ 截斷交給終端機（關掉 DECAWM），不要自己算顯示寬度。
# capture-pane -e 的輸出夾著 SGR 逃逸碼，逐欄截斷得先把它們解析出來才不會
# 把顏色切壞、或把逃逸碼算進欄數。關掉自動換行的話逃逸碼不佔欄位，切點自然對。

set -u
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

MYWIN=${1:-}
SELF=${TMUX_PANE:-}

stty -echo 2>/dev/null
printf '\033[?7l\033[?25l'          # 關自動換行、藏游標

# 收尾一定要自己 exit：訊號的 handler 跑完會繼續往下走，
# 只寫 trap 不 exit 等於把「窗格關掉就結束」拆掉（同 docs 規則 7）。
cleanup() { printf '\033[?7h\033[?25h' 2>/dev/null; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP QUIT

while :; do
    # 自己這格沒了就結束。不能用 `display -p -t "$SELF" ''` 判斷 ——
    # 那對已刪除的 pane 一樣回 rc=0（docs 規則 13）。
    ab_alive "$SELF" || exit 0

    t=$(tmux show-options -wqv -t "$MYWIN" "$K_MIRROR" 2>/dev/null)
    h=$(tmux display -p -t "$SELF" '#{pane_height}' 2>/dev/null)

    if [ -n "$t" ] && ab_alive "$t" && [ "${h:-0}" -gt 1 ]; then
        # \033[H 覆蓋式重畫 + 每行 \033[K + 收尾 \033[J。
        # 用 \033[2J 清空是肉眼看得到的一閃，每秒閃一次會很煩。
        { printf '\033[H'
          # ⚠️ 內部的空行一定要留著。Claude Code 的版面是靠空行撐開的
          # （訊息之間的間隔、輸入框上下的留白），濾掉之後畫面會被壓扁，
          # 跟走進去看到的對不起來。實測 14 行會變成 10 行。
          #
          # 只砍**尾端**的空白列：來源的可見畫面等於它整格的高度，
          # 內容只有前幾行時後面全是空的，照單全收的話鏡像會是一整片空白。
          #
          # 判斷「這行有沒有東西」要先把 SGR 逃逸碼拿掉 ——
          # capture-pane -e 的空行其實含逃逸碼，直接用 NF 判斷會是 1。
          # 逃逸字元用 sprintf 產生，不要寫成 regex 字面值（三種 awk 解讀不一致）。
          tmux capture-pane -p -e -t "$t" 2>/dev/null \
            | awk -v H="$h" '
                BEGIN { RE = sprintf("%c", 27) "\\[[0-9;?]*[a-zA-Z]" }
                { raw[++n] = $0
                  t = $0; gsub(RE, "", t); gsub(/[ \t]+$/, "", t)
                  if (t != "") last = n }
                END { if (last == 0) last = n
                      s = (last > H ? last - H + 1 : 1)
                      for (i = s; i <= last; i++) printf "%s\033[K\n", raw[i] }'
          printf '\033[J'
        } 2>/dev/null
    fi
    sleep 1
done
