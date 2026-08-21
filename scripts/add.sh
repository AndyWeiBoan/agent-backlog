#!/bin/sh
# add <標題>，內容從 stdin。建 detached window，不啟動 claude。
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"
[ $# -ge 1 ] || { echo "用法: add.sh <標題>  (內容從 stdin)" >&2; exit 1; }
body=$(cat)
printf '%s' "$body" > "${TMPDIR:-/tmp}/ab-add.$$"
id=$(tmux new-window -d -n "$1" -P -F '#{window_id}')
# 寫不進去（超過 tmux 約 16 KB 的指令長度上限）就把 window 收掉，
# 不要留一則出現在清單上但打開是空的待辦。
if ! ab_set_prompt "$id" "${TMPDIR:-/tmp}/ab-add.$$"; then
    tmux kill-window -t "$id" 2>/dev/null
    rm -f "${TMPDIR:-/tmp}/ab-add.$$"
    printf '沒有新增：內容 %s bytes，超過 tmux 的指令長度上限（約 16 KB）\n' \
        "$(printf '%s' "$body" | LC_ALL=C wc -c | tr -d ' ')" >&2
    exit 1
fi
rm -f "${TMPDIR:-/tmp}/ab-add.$$"
tmux set-option -w -t "$id" "$K_STATUS" pending
# 新增一則也會改變順序（清單最後是照標題排的），所以要同步 window 順序
ab_sync_order "$(ab_session_of "$id")"
printf '%s\n' "$id"
