# 共用：option key、清單查詢、寬度處理
# 這個檔只被 source，不獨立執行。

PREFIX=agent_backlog
K_PROMPT="@${PREFIX}_prompt"
K_STATUS="@${PREFIX}_status"
K_CURSOR="@${PREFIX}_cursor"     # 目前選中的 window_id，存成 global option
                                 # 理由：client-resized hook 是另一個行程，讀不到 sh 變數
K_PRIORITY="@${PREFIX}_priority" # 1..10，越大越先做。沒設 = 1
K_RETURN="@${PREFIX}_return"     # 開選單之前所在的 window，取消時回去
K_HOME="@${PREFIX}_home"         # 最後一次「從不是待辦的 window」開選單的地方
                                 # 跟 K_RETURN 不一樣，見 open.sh 的說明
K_WIDTH="@${PREFIX}_width"       # 左窗格寬度，記住使用者調過的

# 欄位分隔符用 tab。
# 原本用 ASCII unit separator (0x1F)，但 tmux 3.4 會把控制字元逃逸成字面的
# 「\037」六個字元輸出（3.6a 不會）—— 只在 macOS 上測永遠看不到這件事。
# tab 兩個版本都原樣通過。docs 裡「不要用 tab」的警告是指預設 IFS/FS 會併連續
# 欄位；這裡 awk 用明確分隔符 split、shell 用 cut -d，都不會併。
US=$(printf '\t')

# 某個 window（@…）或 pane（%…）還在不在。
#
# ⚠️ 不可以用 `tmux display -p -t "$id" '' >/dev/null 2>&1` 判斷。
# 實測 tmux 3.6a 對**已經不存在**的 window / pane 一樣回 rc=0（輸出是空的），
# 那個寫法等於完全沒有檢查。只能拿實際的清單來比對。
# 用 shell 的迴圈而不是 grep —— grep 不在 agent-backlog.tmux 的依賴清單裡。
ab_alive() {
    _id=${1:-}
    [ -z "$_id" ] && return 1
    case $_id in
        %*) _c=list-panes;   _f='#{pane_id}'   ;;
        *)  _c=list-windows; _f='#{window_id}' ;;
    esac
    for _x in $(tmux "$_c" -a -F "$_f" 2>/dev/null); do
        [ "$_x" = "$_id" ] && return 0
    done
    return 1
}

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
# 介面語言。預設英文 —— 這是要公開的 plugin，繁中請設 @agent_backlog_lang zh-TW。
AB_LANG=$(tmux show-options -gqv "@${PREFIX}_lang" 2>/dev/null)
case $AB_LANG in zh|zh-TW|zh_TW) AB_LANG=zh ;; *) AB_LANG=en ;; esac

AB_SCOPE=$(tmux show-options -gqv "@${PREFIX}_scope" 2>/dev/null)
[ -z "$AB_SCOPE" ] && AB_SCOPE=session

# 派工時在那個 window 裡打什麼指令。預設 claude。
#
# 這裡不寫死 claude 的兩個理由：
#
# 1. agent 不只一種。codex / opencode / pi 都是同樣的用法 ——
#    我們要做的只是「不要替使用者決定」。
#
# 2. 權限模式。派工的重點是丟出去就不用管它，但 Claude Code 預設會停下來問
#    「Do you want to proceed?」—— 那你就得走進每一個 window 按 Yes，
#    整個派工就沒意義了。要免問就設：
#        set -g @agent_backlog_dispatch_cmd 'claude --permission-mode bypassPermissions'
#
# 3. 旗標是使用者的事，不是這裡的事。這整串原樣送進那個 pane 的 shell，
#    所以任何旗標都直接能用 —— 例如讓派出去的 agent 卡住時去問更強的模型：
#        … 'claude --permission-mode bypassPermissions --advisor fable'
#    這也是為什麼這裡不該長出第二個「顧問模型」選項：已經做得到的事不必再開一個洞。
#
# ⚠️ 預設**不會**幫你開 bypassPermissions。那等於任何人裝了這個 plugin，
#    派出去的 agent 就能在他的 repo 裡無條件做任何事（刪檔、push、對外連線）。
#    那是使用者自己該做的決定，不是 plugin 的預設值。
AB_DISPATCH_CMD=$(tmux show-options -gqv "@${PREFIX}_dispatch_cmd" 2>/dev/null)
[ -z "$AB_DISPATCH_CMD" ] && AB_DISPATCH_CMD=claude

# 列出待辦：window_id US 狀態 US 標題 US 優先度
# $1 可覆寫範圍（session / global），給選單的即時切換用。
#
# 排序在這裡做，不在呼叫端 —— 選單、MCP、backup 全部走這支，
# 所以「順序」只有一個定義。不然人看到的順序會跟 agent 看到的不一樣。
#
# LC_ALL=C 是為了讓標題的比較是位元組序：三種 awk 一致，跟系統 locale 無關。
# 沒有它的話同一份清單在不同機器上順序會不同。
#
# ⚠️ 用 $DIR 找 sort.awk。每個進入點都在 source 這個檔之前設好 DIR
# （add.sh、chooser.sh、mcp-server.sh…），這是這個專案既有的約定。
ab_items() {
    _scope=${1:-$AB_SCOPE}
    _fmt="#{window_id}${US}${AB_STATUS_F}${US}#{window_name}${US}#{$K_PRIORITY}"
    if [ "$_scope" = session ] && [ -n "${AB_SESSION:-}" ]; then
        tmux list-windows -t "$AB_SESSION" -f "$AB_FILTER" -F "$_fmt"
    else
        tmux list-windows -a -f "$AB_FILTER" -F "$_fmt"
    fi | LC_ALL=C awk -f "${DIR:-.}/sort.awk"
}

# 讓某個 session 的 window 順序等於清單順序。
#
# 為什麼要做這件事：清單的排序只影響我們畫出來的東西，tmux 自己的 window 列表、
# 狀態列、C-b w 全部照 window_index 排。不同步的話，同一批待辦從兩個門進來
# 看到的先後不一樣。
#
# ⚠️ swap-window 會改動「當前 window」，所以事後一定要選回來。
#
# tmux 的當前 window 是記 index 的。實測：人在 win 2 看某一則，
# swap 2↔4 之後人還在 win 2，但那已經是另一則了（@154 變成 @156）。
#
# `-d` 不能解決這件事 —— 它只是換一種挑法。實測：active 是完全無關的 win 0
# （非待辦），swap 完之後當前變成了 -s 那個 window。
# 我第一次「驗證 -d 有效」是假陽性，當時 active 剛好就是 -s。
#
# 所以做法是：先記下原本的當前 window_id，換完再 select-window 選回去。
# 那個 after-select-window 的 hook 是幂等的（選到哪個 window 就設對應的
# key-table），所以多這一次 select 不會弄壞選單的按鍵。
#
# 全部指令用 \; 串成一次呼叫。這是按鍵路徑（C-k / C-j 會連按），
# 十幾次 round trip 會直接吃掉我們壓下來的延遲。
ab_sync_order() {
    [ -n "${AB_NO_SYNC:-}" ] && return 0
    _s=$1
    [ -z "$_s" ] && return 0
    _act=$(tmux display -p -t "$_s" '#{window_id}' 2>/dev/null)
    {
        tmux list-windows -t "$_s" -f "$AB_FILTER" \
            -F "S${US}#{window_index}${US}#{window_id}" 2>/dev/null
        # ⚠️ 不要寫成 `AB_SESSION=$_s ab_items session`。前置賦值套在**函式**上，
        # POSIX 說行為未定義，而實測在 macOS 的 /bin/sh 上會外洩 ——
        # 呼叫結束後 AB_SESSION 還是被改掉的值。
        # 這個 { } 是管線左側，本身就是 subshell，所以直接指定就好，不會外洩。
        AB_SESSION=$_s
        ab_items session | awk -F"$US" '{print "D\t" $1}'
    } | awk -f "${DIR:-.}/reorder.awk" \
      | {
          # ⚠️ 這裡不能用 eval 組字串。session id 長得像「$8」——
          # eval 會把它當成第 8 個位置參數展開，變成空的或別的東西
          # （實測：'$16:2' 經過 eval 變成 '6:2'）。
          # 用位置參數累積，tmux "$@" 一次送完，字串永遠不會被二次展開。
          set --
          while read -r a b; do
              [ $# -gt 0 ] && set -- "$@" ';'
              set -- "$@" swap-window -d -s "$_s:$a" -t "$_s:$b"
          done
          # 已經是對的順序 → 一個 swap 都不用，也就不必呼叫 tmux
          if [ $# -gt 0 ]; then
              # 把人選回原本那個 window（不是原本那個 index）
              [ -n "$_act" ] && set -- "$@" ';' select-window -t "$_act"
              tmux "$@" 2>/dev/null
          fi
          : ; }
}

# 從 window_id 反推它住在哪個 session。優先度與狀態都是「那則自己的事」，
# 所以重排的範圍是它所在的 session，跟使用者當下看的是 session 還是 global 無關。
ab_session_of() { tmux display -p -t "$1" '#{session_id}' 2>/dev/null; }

# ── 刪除前的最後一份副本 ──────────────────────────────────
#
# 這個系統沒有 undo、沒有版本歷史、沒有持久化。刪掉就是真的沒了。
# 所以刪之前把整則塞進一個具名的 tmux buffer，格式跟 backup.sh 的 dump 一樣，
# 要救回來就是：
#     tmux show-buffer -b agent_backlog_deleted > /tmp/x
#     sh scripts/restore.sh /tmp/x
#
# 存進 tmux buffer 而不是寫檔，是因為這個工具本來就不在磁碟上放東西 ——
# 而 buffer 剛好是 tmux 已經提供的暫存區，不用我們自己管生命週期。
# 只留最後一則（buffer 同名會覆蓋）。這不是備份機制，是給「手滑」一次機會。
AB_STASH_BUF="agent_backlog_deleted"
ab_stash() {
    _id=$1
    _f=$(mktemp) || return 0
    {
        printf '@@ITEM2 %s\t%s\t%s\n' \
            "$(tmux display -p -t "$_id" '#{window_name}' 2>/dev/null)" \
            "$(tmux display -p -t "$_id" "$AB_STATUS_F" 2>/dev/null)" \
            "$(tmux show-options -w -qv -t "$_id" "$K_PRIORITY" 2>/dev/null)"
        ab_prompt "$_id"
    } > "$_f"
    tmux load-buffer -b "$AB_STASH_BUF" "$_f" 2>/dev/null
    rm -f "$_f"
}

# 那個 window 裡有沒有東西在跑。
#
# 「有沒有在跑」是觀察來的，不是記錄的 —— 看 pane 實際在執行什麼。
# ⚠️ 不能拿「等於 claude」來判斷：Claude Code 的 pane_current_command 是版本字串
# （實測是 2.1.220），不是 claude。所以反過來問：是不是一個閒置的 shell。
# 認不出來的一律當成「有東西在跑」，寧可擋下來也不要砍掉別人正在做的事。
ab_is_idle() {
    case $(tmux display -p -t "$1" '#{pane_current_command}' 2>/dev/null) in
        sh|bash|zsh|fish|dash|ksh|mksh|ash|tcsh|csh) return 0 ;;
        *) return 1 ;;
    esac
}

# 寫優先度。夾在 1..10 —— 超出範圍的值會讓排序看起來像壞掉，
# 而這個值有三個來源（人按鍵、MCP、手動 set-option），在最靠資料的地方夾一次最省。
ab_set_priority() {
    _p=$2
    case $_p in ''|*[!0-9]*) _p=1 ;; esac
    [ "$_p" -lt 1 ]  && _p=1
    [ "$_p" -gt 10 ] && _p=10
    tmux set-option -w -t "$1" "$K_PRIORITY" "$_p" 2>/dev/null
    ab_sync_order "$(ab_session_of "$1")"
}

# 取某則的原始 markdown。
# 用 display -p 而不是 show-options -v，因為要讓 format 決定讀哪個 key。
# 實測多行內容、引號、反引號都與 show-options 逐位元組相同。
ab_prompt() {
    tmux display -p -t "$1" "$AB_PROMPT_F" 2>/dev/null
}

# 寫狀態。相容模式下要寫回「這則原本用的那個 key」，否則就分岔了。
#
# 狀態也是排序鍵（done 會沉底），所以改完一樣要同步 window 順序。
# 漏掉這裡的話會出現「標成 done 之後清單裡沉下去了，狀態列卻還在原位」。
ab_set_status() {
    if [ "$AB_COMPAT" = on ] &&
       [ -z "$(tmux show-options -w -qv -t "$1" "$K_PROMPT" 2>/dev/null)" ]; then
        tmux set-option -w -t "$1" @status "$2" 2>/dev/null
    else
        tmux set-option -w -t "$1" "$K_STATUS" "$2" 2>/dev/null
    fi
    ab_sync_order "$(ab_session_of "$1")"
}
