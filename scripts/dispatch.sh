#!/bin/sh
# 派工：在該待辦的 window 裡啟動一個獨立的 claude 實例，把內容送進去。
# 用法：dispatch.sh <window_id>
#
# 送內容用 tmux 的 buffer（load-buffer / paste-buffer），不是 send-keys 拼字串。
# 理由：內容是 markdown，含引號、反引號、換行，拼進命令列一定會被 shell 解析壞掉。
# 舊版是先寫暫存檔再 send-keys，buffer 更乾淨 —— 完全不經過 shell。

set -u
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

# 訊息雙語：$1 中文、$2 英文
msg() { [ "$AB_LANG" = zh ] && printf '%s' "$1" || printf '%s' "$2"; }

id=${1:-}
[ -z "$id" ] && { echo "用法: dispatch.sh <window_id>" >&2; exit 1; }

# 刻意不用 command -v claude 先檢查：
# 這支是被 tmux run-shell 起來的，繼承的是 tmux server 當初的 PATH，
# 不是那個 pane 的互動 shell 的 PATH（後者才會載入 profile）。
# 改成先送指令、再看 pane 有沒有真的變成 claude，用結果判斷。

# 「在不在跑」不能比對 pane_current_command = claude ——
# 實測 Claude Code 的行程名稱是版本字串（例如 2.1.220），不是 "claude"。
# 改成反過來判斷：只要不是 shell，就當作有東西在跑。
is_shell() {
    case ${1:-} in
        sh|ash|dash|bash|zsh|fish|ksh|tcsh|csh|login) return 0 ;;
        *) return 1 ;;
    esac
}

shell_before=$(tmux display -p -t "$id" '#{pane_current_command}' 2>/dev/null)
if ! is_shell "$shell_before"; then
    tmux display-message -d 3000 "$(msg "agent-backlog: 這則已經在跑了（$shell_before）" "agent-backlog: already running ($shell_before)")"
    exit 0
fi

f=$(mktemp /tmp/ab-dispatch.XXXXXX)
ab_prompt "$id" > "$f"
if [ ! -s "$f" ]; then
    rm -f "$f"
    tmux display-message -d 3000 "$(msg "agent-backlog: 這則沒有內容" "agent-backlog: this item has no content")"
    exit 1
fi

tmux send-keys -t "$id" claude Enter

# 等 claude 起來再貼內容。太早貼會被還沒準備好的 TUI 吃掉。
# macOS 沒有 timeout/gtimeout，所以用 until 迴圈自己數。
# 等到 pane 跑的東西「跟剛才不一樣」為止。
# 不比對 = claude，因為 Claude Code 的行程名稱是版本字串（實測 2.1.220）；
# 也不只用 is_shell，因為包裝腳本可能本身就是 shell。
n=0
while [ "$(tmux display -p -t "$id" '#{pane_current_command}' 2>/dev/null)" = "$shell_before" ] \
      && [ $n -lt 30 ]; do
    sleep 1
    n=$((n + 1))
done
if [ "$(tmux display -p -t "$id" '#{pane_current_command}' 2>/dev/null)" = "$shell_before" ]; then
    rm -f "$f"
    tmux display-message -d 4000 "$(msg "agent-backlog: claude 沒有起來（那個 pane 的 PATH 裡有嗎？）" "agent-backlog: claude did not start (is it on that pane PATH?)")"
    exit 1
fi
sleep 1        # 起來之後再給它一點時間畫完輸入框

tmux load-buffer -b agent_backlog_dispatch "$f"
tmux paste-buffer -b agent_backlog_dispatch -t "$id"
tmux delete-buffer -b agent_backlog_dispatch 2>/dev/null
rm -f "$f"

sleep 1
tmux send-keys -t "$id" Enter

ab_set_status "$id" running
tmux display-message -d 3000 \
    "agent-backlog: $(msg '已派工給' 'dispatched to') $(tmux display -p -t "$id" '#{window_name}')"
