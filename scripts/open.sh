#!/bin/sh
# 入口：開一個 backlog window 跑選單。已經開著就切過去。
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

# session 由呼叫端傳進來（綁鍵時用 #{session_id}，run-shell 會在按鍵當下展開）。
#
# ⚠️ 不能在這裡自己 `tmux display -p '#{session_id}'` —— 沒有 target 的話 tmux
# 用的是「當前 session」，而 run-shell 起來的行程沒有 client 脈絡，
# 拿到的常常是別的 session。實測：在 beta 按鍵，這裡卻回 alpha。
SESS=${1:-}
[ -z "$SESS" ] && SESS=$(tmux display -p '#{session_id}')

# 只找「這個 session 裡」已經開著的選單。
#
# ⚠️ 不要用 list-windows -a。找到別的 session 的選單之後 select-window 只會改
# 那個 session 的當前 window，使用者的畫面完全不動 —— 按下去像壞掉一樣。
# 而且每個 session 本來就該有自己的選單：它會動到 session 層級的 key-table，
# 共用一個反而互相打架。
W=$(tmux list-windows -t "$SESS" -F '#{window_id} #{window_name}' \
    | awk '$2=="[backlog]"{print $1; exit}')
if [ -n "$W" ]; then tmux select-window -t "$W"; exit 0; fi

# 記住開選單之前在哪 —— 取消時要回得去，不然使用者會掉在某個待辦的 shell 裡。
# 存在 session 層級，這樣不同 session 各記各的。
CUR=$(tmux display -p '#{window_id}')
tmux set-option -t "$SESS" "$K_RETURN" "$CUR" 2>/dev/null

# 「家」= 最後一次從**不是待辦**的 window 開選單的地方。C-o 靠這個回去。
#
# ⚠️ 為什麼要跟 K_RETURN 分開存：
# K_RETURN 每次開選單都會被覆蓋。所以「在工作區開選單 → Enter 進某則待辦 →
# 再開選單」之後，K_RETURN 已經變成那則待辦，而工作區那個 window **不在清單裡**
# （它沒有 prompt option），plugin 也不再記得它 —— 使用者就再也回不去了。
# 只在「現在不是待辦」時才更新，工作區的位置才活得過這條路徑。
if [ "$(tmux display -p -t "$CUR" "$AB_FILTER" 2>/dev/null)" != 1 ]; then
    tmux set-option -t "$SESS" "$K_HOME" "$CUR" 2>/dev/null
fi
# 明確指定 session。不指定的話 tmux 會用「當前的」——
# 從 hook / run-shell 之類的非互動情境呼叫時，那不一定是使用者所在的 session，
# 選單就會開到別的地方去（然後看起來像沒反應）。
tmux new-window -t "$SESS" -n '[backlog]' "sh '$DIR/chooser.sh'"
