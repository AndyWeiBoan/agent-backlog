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
          tmux capture-pane -p -e -t "$t" 2>/dev/null \
            | awk 'NF { buf[++n] = $0 }
                   END { s = (n > H ? n - H + 1 : 1)
                         for (i = s; i <= n; i++) printf "%s\033[K\n", buf[i] }' H="$h"
          printf '\033[J'
        } 2>/dev/null
    fi
    sleep 1
done
