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

# 列出所有待辦：window_id US 狀態 US 標題
ab_items() {
    tmux list-windows -a \
        -f "#{!=:#{${K_PROMPT}},}" \
        -F "#{window_id}${US}#{${K_STATUS}}${US}#{window_name}"
}

# 取某則的原始 markdown
ab_prompt() {
    tmux show-options -w -v -t "$1" "$K_PROMPT" 2>/dev/null
}
