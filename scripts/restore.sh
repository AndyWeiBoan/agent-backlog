#!/bin/sh
# 從 backup.sh 產生的檔還原。已經存在的同名待辦會跳過，不覆蓋。
# 用法：restore.sh <檔名> [session]
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

f=${1:?用法: restore.sh <檔名> [session]}
[ -f "$f" ] || { echo "找不到 $f" >&2; exit 1; }

# 還原到哪個 session 一定要講明白。
#
# ⚠️ 原本這裡是 `tmux new-window -d -n "$name"`，沒有 -t —— tmux 會用「當前
# session」，而從非互動情境（script、run-shell、另一個 session 的 shell）跑起來
# 的行程，那個「當前」不一定是你以為的那個。實際踩到過：在測試 session 裡跑
# restore，window 全部落到 session 0 去。
#
# 而預設 scope=session 的情況下，落錯 session 就等於「還原完了但清單是空的」。
SESS=${2:-${AB_SESSION:-$(tmux display -p '#{session_id}' 2>/dev/null)}}
[ -z "$SESS" ] && { echo "抓不到 session，請用 restore.sh <檔名> <session>" >&2; exit 1; }
printf '還原到 session %s（%s）\n' "$SESS" "$(tmux display -p -t "$SESS" '#{session_name}' 2>/dev/null)"

# 「已存在」只看目標 session。
# 看全域的話，把備份還原到另一個 session 會全部被當成重複而跳過 ——
# 而崩潰後還原的情境下，全域跟目標 session 本來就是同一份，沒有差別。
AB_SESSION=$SESS
have=$(mktemp); ab_items session | cut -f3 | sort > "$have"
body=$(mktemp); name=""; st=""; pr=""

flush() {
    [ -z "$name" ] && return 0
    if grep -qxF "$name" "$have"; then
        printf '跳過（已存在）%s\n' "$name"
    else
        id=$(tmux new-window -d -t "$SESS" -n "$name" -P -F '#{window_id}')
        # 這是救援路徑，靜默失敗最不能接受 —— 使用者會以為東西回來了。
        if ! ab_set_prompt "$id" "$body"; then
            tmux kill-window -t "$id" 2>/dev/null
            printf '還原失敗（內容 %s bytes 超過 tmux 約 16 KB 的上限）：%s\n' \
                "$(LC_ALL=C wc -c < "$body" | tr -d ' ')" "$name" >&2
        else
            tmux set-option -w -t "$id" "$K_STATUS" "$st"
            ab_set_priority "$id" "${pr:-1}"
            printf '還原 %s -> %s\n' "$name" "$id"
        fi
    fi
    : > "$body"
}

# 還原過程中不要每建一則就重排一次 window —— n 則會排 n 次，
# 而且中間的順序沒人看。最後統一排一次就好。
AB_NO_SYNC=1

while IFS= read -r line; do
    case $line in
        # 新格式：欄位用 tab 分隔，所以標題有空白也不會解錯
        '@@ITEM2 '*)
            flush
            rest=${line#@@ITEM2 }
            name=$(printf '%s' "$rest" | cut -f1)
            st=$(printf '%s' "$rest" | cut -f2)
            pr=$(printf '%s' "$rest" | cut -f3)
            ;;
        # 舊格式（沒有優先度）：狀態是最後一個以空白分隔的詞。
        # 保留是因為你手上已經有這種 dump —— 那是真的救過資料的檔。
        '@@ITEM '*)
            flush
            rest=${line#@@ITEM }
            name=${rest% *}
            st=${rest##* }
            pr=1
            ;;
        *) printf '%s\n' "$line" >> "$body" ;;
    esac
done < "$f"
flush
rm -f "$body" "$have"

AB_NO_SYNC=
ab_sync_order "$SESS"
