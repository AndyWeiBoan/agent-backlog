#!/bin/sh
# 入口：開一個 backlog window 跑選單。已經開著就切過去。
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

W=$(tmux list-windows -a -F '#{window_id} #{window_name}' | awk '$2=="[backlog]"{print $1; exit}')
if [ -n "$W" ]; then tmux select-window -t "$W"; exit 0; fi

# 記住開選單之前在哪 —— 取消時要回得去，不然使用者會掉在某個待辦的 shell 裡
tmux set-option -g "$K_RETURN" "$(tmux display -p '#{window_id}')" 2>/dev/null
tmux new-window -n '[backlog]' "sh '$DIR/chooser.sh'"
