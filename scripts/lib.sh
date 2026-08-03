# 共用：option key、清單查詢、寬度處理
# 這個檔只被 source，不獨立執行。

PREFIX=agent_backlog
K_PROMPT="@${PREFIX}_prompt"
K_STATUS="@${PREFIX}_status"
K_CURSOR="@${PREFIX}_cursor"     # 目前選中的 window_id，存成 global option
                                 # 理由：client-resized hook 是另一個行程，讀不到 sh 變數
K_RETURN="@${PREFIX}_return"     # 開選單之前所在的 window，取消時回去
K_WIDTH="@${PREFIX}_width"       # 左窗格寬度，記住使用者調過的

# 欄位分隔符用 tab。
# 原本用 ASCII unit separator (0x1F)，但 tmux 3.4 會把控制字元逃逸成字面的
# 「\037」六個字元輸出（3.6a 不會）—— 只在 macOS 上測永遠看不到這件事。
# tab 兩個版本都原樣通過。docs 裡「不要用 tab」的警告是指預設 IFS/FS 會併連續
# 欄位；這裡 awk 用明確分隔符 split、shell 用 cut -d，都不會併。
US=$(printf '\t')

# ── 相容模式 ──────────────────────────────────────────
# @agent_backlog_compat = on 時，連舊版 action-items 的 @prompt / @status 也一起認。
#
# 為什麼需要：新舊並行時如果各存各的 key，同一則待辦就有兩份狀態，
# 改了一邊另一邊不會動，很快就分岔。相容模式讓兩套讀同一份資料 ——
# 舊的那些留在舊 key 上不動，新版直接讀它，狀態也寫回原本的 key。
# 這樣「切換」就只是換一個鍵按，不是資料遷移。
AB_COMPAT=$(tmux show-options -gqv "@${PREFIX}_compat" 2>/dev/null)

if [ "$AB_COMPAT" = on ]; then
    AB_FILTER="#{||:#{!=:#{$K_PROMPT},},#{!=:#{@prompt},}}"
    AB_PROMPT_F="#{?#{$K_PROMPT},#{$K_PROMPT},#{@prompt}}"
    AB_STATUS_F="#{?#{$K_STATUS},#{$K_STATUS},#{@status}}"
else
    AB_FILTER="#{!=:#{$K_PROMPT},}"
    AB_PROMPT_F="#{$K_PROMPT}"
    AB_STATUS_F="#{$K_STATUS}"
fi

# ── 範圍 ──────────────────────────────────────────────
# @agent_backlog_scope = session（預設）只看自己 session 的待辦；global 看全部。
#
# 「屬於哪個 session」= 那個 window 現在住在哪個 session。
# 不另外記「由誰建立」—— window 幾乎不會被 move-window 搬走，
# 而且「東西在哪就歸哪」比「認出生地」直覺，也不會出現
# 「這則明明在我眼前，清單卻說不屬於我」這種鬼故事。
#
# 呼叫端要先設 AB_SESSION（chooser 用自己的 $SESS，MCP 由 TMUX_PANE 反推）。
# 推不出來就退回全域 —— 寧可多顯示，也不要讓人以為待辦不見了。
AB_SCOPE=$(tmux show-options -gqv "@${PREFIX}_scope" 2>/dev/null)
[ -z "$AB_SCOPE" ] && AB_SCOPE=session

# 列出待辦：window_id US 狀態 US 標題
# $1 可覆寫範圍（session / global），給選單的即時切換用。
ab_items() {
    _scope=${1:-$AB_SCOPE}
    if [ "$_scope" = session ] && [ -n "${AB_SESSION:-}" ]; then
        tmux list-windows -t "$AB_SESSION" -f "$AB_FILTER" \
            -F "#{window_id}${US}${AB_STATUS_F}${US}#{window_name}"
    else
        tmux list-windows -a -f "$AB_FILTER" \
            -F "#{window_id}${US}${AB_STATUS_F}${US}#{window_name}"
    fi
}

# 取某則的原始 markdown。
# 用 display -p 而不是 show-options -v，因為要讓 format 決定讀哪個 key。
# 實測多行內容、引號、反引號都與 show-options 逐位元組相同。
ab_prompt() {
    tmux display -p -t "$1" "$AB_PROMPT_F" 2>/dev/null
}

# 寫狀態。相容模式下要寫回「這則原本用的那個 key」，否則就分岔了。
ab_set_status() {
    if [ "$AB_COMPAT" = on ] &&
       [ -z "$(tmux show-options -w -qv -t "$1" "$K_PROMPT" 2>/dev/null)" ]; then
        tmux set-option -w -t "$1" @status "$2" 2>/dev/null
    else
        tmux set-option -w -t "$1" "$K_STATUS" "$2" 2>/dev/null
    fi
}
