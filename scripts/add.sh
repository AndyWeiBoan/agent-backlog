#!/bin/sh
# add <標題>，內容從 stdin。建 detached window，不啟動 claude。
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"
[ $# -ge 1 ] || { echo "用法: add.sh <標題>  (內容從 stdin)" >&2; exit 1; }
body=$(cat)
id=$(tmux new-window -d -n "$1" -P -F '#{window_id}')
tmux set-option -w -t "$id" "$K_PROMPT" "$body"
tmux set-option -w -t "$id" "$K_STATUS" pending
printf '%s\n' "$id"
