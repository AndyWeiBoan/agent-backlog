#!/usr/bin/env sh
# TPM 入口。TPM 對 plugin 的定義就是「一個 git repo ＋ 至少一個可執行的 *.tmux」，
# 安裝時把它 source 一遍就完事，沒有 API、沒有註冊流程。
#
# 這支只做三件事：檢查環境、讀設定、綁鍵。真正的東西都在 scripts/。

DIR="$(cd "$(dirname "$0")" && pwd)"

# 這支是被 tmux source 的，錯誤訊息沒有地方可以印 —— 只能用 display-message，
# 而且要留得住（display-time 預設 750ms 太短，看不到）。
ab_fail() {
    tmux display-message -d 4000 "agent-backlog: $1"
    exit 1
}

# ── 支援的平台：macOS 與 Linux ────────────────────────
case "$(uname -s)" in
    Darwin|Linux) ;;
    *) ab_fail "只支援 macOS 與 Linux（偵測到 $(uname -s)）" ;;
esac

# ── tmux 版本 ─────────────────────────────────────────
# 需要 3.0 以上。用到的東西裡最晚出現的是 send-keys -X 與 after-resize-pane
# （2.4 就有），但實測只涵蓋 3.4 與 3.6a，所以門檻拉在 3.0 而不是 2.4。
ab_version_ok() {
    v=$(tmux -V | sed 's/^tmux //; s/^next-//')     # "3.6a" / "next-3.4" 都吃得到
    major=$(printf '%s' "$v" | sed 's/[^0-9].*//')
    [ -z "$major" ] && return 1                     # 版本字串認不得就當不合格
    [ "$major" -ge 3 ]
}
ab_version_ok || ab_fail "需要 tmux 3.0 以上（目前 $(tmux -V)）"

# ── 外部指令 ──────────────────────────────────────────
# 全部是 POSIX，macOS 與 Linux 都內建。列出來是為了讓缺東西時的錯誤訊息看得懂，
# 而不是在選單裡莫名其妙壞掉。
for c in awk sed stty dd od cut mkfifo mktemp; do
    command -v "$c" >/dev/null 2>&1 || ab_fail "找不到 $c"
done

# ── 設定 ──────────────────────────────────────────────
# @agent_backlog_key      開選單的鍵（prefix 之後），預設 A
# @agent_backlog_no_key   設成 on 就完全不綁鍵，自己在 .tmux.conf 裡綁
key=$(tmux show-options -gqv '@agent_backlog_key')
[ -z "$key" ] && key=A
nokey=$(tmux show-options -gqv '@agent_backlog_no_key')

if [ "$nokey" != "on" ]; then
    tmux bind-key "$key" run-shell "sh '$DIR/scripts/open.sh'"
fi

# 給使用者自己綁用的：run-shell "sh #{@agent_backlog_path}/scripts/open.sh"
tmux set-option -g '@agent_backlog_path' "$DIR"
