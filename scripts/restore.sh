#!/bin/sh
# 從 backup.sh 產生的檔還原。已經存在的同名待辦會跳過，不覆蓋。
# 用法：restore.sh <檔名>
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

f=${1:?用法: restore.sh <檔名>}
[ -f "$f" ] || { echo "找不到 $f" >&2; exit 1; }

have=$(mktemp); ab_items | cut -f3 | sort > "$have"
body=$(mktemp); name=""; st=""

flush() {
    [ -z "$name" ] && return 0
    if grep -qxF "$name" "$have"; then
        printf '跳過（已存在）%s\n' "$name"
    else
        id=$(tmux new-window -d -n "$name" -P -F '#{window_id}')
        tmux set-option -w -t "$id" "$K_PROMPT" "$(cat "$body")"
        tmux set-option -w -t "$id" "$K_STATUS" "$st"
        printf '還原 %s -> %s\n' "$name" "$id"
    fi
    : > "$body"
}

while IFS= read -r line; do
    case $line in
        '@@ITEM '*)
            flush
            rest=${line#@@ITEM }
            name=${rest% *}
            st=${rest##* }
            ;;
        *) printf '%s\n' "$line" >> "$body" ;;
    esac
done < "$f"
flush
rm -f "$body" "$have"
