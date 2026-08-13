#!/bin/sh
# 回工作區：不管現在在選單裡、在某則待辦裡、還是在派出去的 agent 那格，
# 都回到這個 session 的工作區。
#
# 用法：home.sh <session_id>
#
# 「工作區」的定義跟選單裡的 C-o 完全一樣（同一份邏輯）：
#   1. @agent_backlog_home —— 上次從「不是待辦」的 window 開選單的地方
#   2. 沒有的話，這個 session 第一個不是待辦、也不是 [backlog] 的 window
# 兩個都沒有就什麼都不做，只出訊息 —— 這個 session 整個都是待辦。

set -u
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

msg() { [ "$AB_LANG" = zh ] && printf '%s' "$1" || printf '%s' "$2"; }

# session 由呼叫端傳進來（綁鍵時用 #{session_id}，run-shell 會在按鍵當下展開）。
# 理由跟 open.sh 一樣：run-shell 起來的行程沒有 client 脈絡，
# 自己問「當前 session」拿到的常常是別的 session。
SESS=${1:-}
[ -z "$SESS" ] && SESS=$(tmux display -p '#{session_id}')

CUR=$(tmux display -p -t "$SESS" '#{window_id}' 2>/dev/null)

H=$(tmux show-options -qv -t "$SESS" "$K_HOME" 2>/dev/null)
ab_alive "$H" || H=$(ab_workspace "$SESS")

if [ -z "$H" ]; then
    tmux display-message -d 4000 "agent-backlog: $(msg \
        '這個 session 每個 window 都是待辦，沒有工作區可以回' \
        'every window in this session is an item; there is no workspace to go back to')"
    exit 0
fi

[ "$H" = "$CUR" ] && exit 0      # 已經在家了

tmux select-window -t "$H" 2>/dev/null

# 剛剛人在選單裡的話順手把它關掉，不然會留一個 [backlog] window 在那。
#
# ⚠️ 先切走再殺。反過來做的話，殺掉 active window 會讓 tmux 自己挑下一個，
# 蓋掉我們剛選的（同 docs 規則 11）。
# 殺掉送的是 SIGHUP，chooser.sh 的 trap 會把 key-table 與 hook 還原。
if [ "$(tmux display -p -t "$CUR" '#{window_name}' 2>/dev/null)" = '[backlog]' ]; then
    tmux kill-window -t "$CUR" 2>/dev/null
fi
