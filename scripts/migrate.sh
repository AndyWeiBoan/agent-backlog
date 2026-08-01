#!/bin/sh
# 舊 key → 新 key。刻意不刪舊的：新舊兩套要能同時活著，
# 這樣回滾只是「不按那個鍵」，不是資料救援。
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"
US=$(printf '\037')
n=0
tmux list-windows -a -f '#{!=:#{@prompt},}' -F "#{window_id}" | while read -r id; do
    p=$(tmux show-options -w -v -t "$id" @prompt 2>/dev/null)
    s=$(tmux show-options -w -v -t "$id" @status 2>/dev/null)
    [ -z "$p" ] && continue
    tmux set-option -w -t "$id" "$K_PROMPT" "$p"
    tmux set-option -w -t "$id" "$K_STATUS" "${s:-pending}"
    n=$((n+1))
    printf '遷移 %s\n' "$id"
done
printf '完成。舊的 @prompt / @status 保留未動。\n'
