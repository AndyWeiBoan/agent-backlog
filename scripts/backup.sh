#!/bin/sh
# 把所有待辦匯出成一個檔。相容模式下連舊 key 的也一起匯。
# 用法：backup.sh [檔名]   預設 ~/agent-backlog-YYYYmmdd-HHMMSS.dump
#
# 為什麼需要：待辦活在 tmux server 記憶體裡，server 沒了就沒了。
# 這不是「發佈前要做的功能」，是自己用就必須有的東西 —— 實際弄丟過 8 則。
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

out=${1:-$HOME/agent-backlog-$(date +%Y%m%d-%H%M%S).dump}
: > "$out"
n=0
ab_items | while IFS= read -r line; do
    id=$(printf '%s' "$line" | cut -f1)
    st=$(printf '%s' "$line" | cut -f2)
    nm=$(printf '%s' "$line" | cut -f3)
    printf '@@ITEM %s %s\n' "$nm" "${st:-pending}" >> "$out"
    ab_prompt "$id" >> "$out"
done
n=$(grep -c '^@@ITEM' "$out" 2>/dev/null || echo 0)
printf '%s\n' "$out"
printf '%s 則\n' "$n" >&2
