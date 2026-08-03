#!/bin/sh
# 左窗格：選單迴圈。讀鍵 → 過濾 → 畫清單 → 印預覽。
# 零依賴：tmux / sh / awk / stty / dd / od / sed，全是 POSIX。
#
# 由 open.sh 以 new-window 啟動，所以有自己的 tty。
#
# 效能上有三個刻意的設計，都是為了打字時不卡、不閃：
#   1. 不清整個畫面（見 list.awk）—— \033[2J 每按一鍵閃一次
#   2. 選中項沒變就不重畫預覽 —— 打字時最花時間的就是它
#   3. 讀到一個鍵後先把緩衝區剩下的鍵吃完，再畫一次 —— 快打時只重畫一次

set -u
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"

TMP=$(mktemp -d /tmp/ab.XXXXXX)
ITEMS="$TMP/items"      # 全部待辦
MATCH="$TMP/match"      # 命中的
CACHE="$TMP/cache"      # render 過的預覽，以 window_id 為檔名
FIFO="$TMP/fifo"
mkdir -p "$CACHE"
mkfifo "$FIFO"

LPANE=$TMUX_PANE
MYWIN=$(tmux display -p -t "$LPANE" '#{window_id}')
SESS=$(tmux display -p -t "$LPANE" '#{session_id}')
STTY_SAVE=$(stty -g)
RPANE=""
TARGET=""

# ── 收尾 ──────────────────────────────────────────────
# raw 模式沒還原的話，離開後終端機是廢的，所以 trap 從第一天就要有。
cleanup() {
    stty "$STTY_SAVE" 2>/dev/null
    kt_off 2>/dev/null
    tmux set-hook -t "$SESS" -u after-select-window 2>/dev/null
    for _hk in client-resized client-attached client-detached after-resize-pane; do
        tmux set-hook -gu "$_hk" 2>/dev/null
    done
    rm -rf "$TMP"
}
# HUP 一定要攔：tmux kill-window 送的就是 SIGHUP，漏掉的話收尾完全不會跑
# （實測後果：/tmp/ab.* 一直累積、hook 留著指向死掉的 pane）。
#
# ⚠️ 但訊號的 trap 執行完會「繼續往下跑」，不會自己結束 ——
# 只寫 `trap cleanup HUP` 等於把「終端機關掉就結束」這個預設行為拆掉，
# 然後主迴圈會對著已死的 tty 空轉。實測後果：20 個孤兒行程、11% CPU。
# 訊號的 handler 一定要自己 exit。
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP QUIT

finish() {
    cleanup
    trap - EXIT
    # 沒有選任何東西（ESC / C-c）就回到開選單之前那個 window。
    # 不這樣做的話，殺掉自己之後 tmux 會自己挑一個，使用者會莫名掉在某則待辦的
    # shell 裡 —— 那個 shell 的提示字元跟原本的環境不一樣，看起來像換了台機器。
    [ -z "$TARGET" ] && TARGET=$(tmux show-options -gqv "$K_RETURN" 2>/dev/null)

    # 先把焦點移到目標 window，再殺掉自己這個 window。
    # 反過來做的話，殺掉 active window 會讓 tmux 自己挑下一個，蓋掉我們的選擇。
    #
    # ⚠️ 清單是整個 server 的（list-windows -a），所以選到的那則很可能在**別的
    # session**。這時候只 select-window 是不夠的 —— 它只改那個 session 的當前
    # window，使用者的 client 還留在原地，看起來就像「按了沒反應」。
    # 要再 switch-client 把人帶過去。
    if [ -n "$TARGET" ]; then
        tsess=$(tmux display -p -t "$TARGET" '#{session_id}' 2>/dev/null)
        tmux select-window -t "$TARGET" 2>/dev/null
        if [ -n "$tsess" ] && [ "$tsess" != "$SESS" ]; then
            tmux switch-client -t "$tsess" 2>/dev/null
        fi
    fi
    tmux kill-window -t "$MYWIN" 2>/dev/null
    exit 0
}

# 太小就不要開 —— 版面會爛掉，而且後面所有計算都失去意義。
# （實際遇過：一個 193x1 的 client 附著，tmux 把整個 session 縮到 1 列）
_h=$(tmux display -p -t "$LPANE" '#{pane_height}')
_w=$(tmux display -p -t "$LPANE" '#{pane_width}')
if [ "${_h:-0}" -lt 10 ] || [ "${_w:-0}" -lt 40 ]; then
    printf '視窗太小（%sx%s），至少要 40x10。\r\n' "${_w:-?}" "${_h:-?}"
    printf '若有很小的 client 附著在同一個 session，tmux 會把大家一起縮小：\r\n'
    printf '  tmux list-clients -F "#{client_tty} #{client_width}x#{client_height}"\r\n'
    printf '按任意鍵關閉。\r\n'
    dd bs=1 count=1 >/dev/null 2>&1
    exit 1
fi

# ── 預覽窗格 ──────────────────────────────────────────
RPANE=$(tmux split-window -h -l 62% -P -F '#{pane_id}' -t "$LPANE" \
        "sh '$DIR/preview_pane.sh' '$FIFO'")
tmux select-pane -t "$LPANE"

# 套用上次調過的寬度
_saved=$(tmux show-options -gqv "$K_WIDTH" 2>/dev/null)
[ -n "$_saved" ] && tmux resize-pane -t "$LPANE" -x "$_saved" 2>/dev/null

# 空的 target 對 tmux 來說等於「當前的」——  kill-window -t "" 會殺掉使用者
# 正在看的 window。寧可整支不啟動，也不要拿空字串去下指令。
if [ -z "$RPANE" ] || [ -z "$MYWIN" ]; then
    printf '無法建立預覽窗格，中止（RPANE=%s MYWIN=%s）\r\n' "$RPANE" "$MYWIN"
    dd bs=1 count=1 >/dev/null 2>&1
    exit 1
fi

# resize 之後 tmux 不會重排已經印出的內容（實測：直接截掉），所以要重印。
# hook 是另一個行程，沒辦法叫醒卡在 dd 的迴圈 —— 改成送一個 C-l 給我們自己，
# 迴圈讀到就重量尺寸並重畫。
# 讓按鍵跳過使用者的 root key table。
#
# 沒有這段的話，使用者 ~/.tmux.conf 裡任何 `bind -n` 都會在按鍵到達我們之前
# 攔走（實際遇到的：C-d 開分割、C-p 選 session、C-t 開新 window、C-s 分割、
# C-w 殺 pane、M-方向鍵切窗格）。挑鍵閃避沒有用 —— 下一台機器就是另一組 config。
# 指到一張不存在的表就等於「什麼都沒綁」，所有按鍵直接落到程式手上。
#
# ⚠️ key-table 是 **session 層級**的選項。`set -w` / `set -p` 都會被 tmux
# 悄悄轉成 session —— 所以它不會隨著我們的 window 一起消失。
# 沒有還原的話，整個 session 從此跳過 root 表，使用者的 C-p / C-t / C-d
# 全部失效，而且看不出原因。一定要存舊值、離開時還原。
KT_OLD=$(tmux show-options -qv -t "$SESS" key-table 2>/dev/null)
kt_off() {
    if [ -n "$KT_OLD" ]; then tmux set-option -t "$SESS" key-table "$KT_OLD" 2>/dev/null
    else tmux set-option -t "$SESS" -u key-table 2>/dev/null; fi
}
kt_on() { tmux set-option -t "$SESS" key-table agent-backlog 2>/dev/null; }
kt_on

# 切到別的 window 時要把 root 表還回去，不然使用者離開選單去做別的事，
# 快捷鍵是壞的。回到選單再關掉。純 tmux 條件式，不用額外開行程。
if [ -n "$KT_OLD" ]; then _kt_restore="set-option -t $SESS key-table $KT_OLD"
else _kt_restore="set-option -t $SESS -u key-table"; fi
tmux set-hook -t "$SESS" after-select-window \
    "if -F '#{==:#{window_id},$MYWIN}' 'set-option -t $SESS key-table agent-backlog' '$_kt_restore'" \
    2>/dev/null

# 任何可能改變尺寸的事件都叫我們重畫。
# client-attached / client-detached 也要掛：另一個 client 離開時 session 會變回
# 大尺寸，但 tmux 不會為此對剩下的 client 發 client-resized —— 少了這兩個，
# 從「視窗太小」狀態就回不來。
for _hk in client-resized client-attached client-detached; do
    tmux set-hook -g "$_hk" "send-keys -t $LPANE C-l"
done

# 調整分隔線寬度：不自己搶鍵，用 tmux 原本就有的 resize-pane（prefix + ⌥←→），
# 調完再靠這個 hook 回頭叫我們重畫並記住寬度。
#
# 為什麼不自己綁鍵：macOS 把 Ctrl+←→ 拿去切換桌面空間；而 Option+←→ 在使用者的
# ~/.tmux.conf 裡已經是 root table 的 select-pane —— tmux 會先攔下來，
# 那些位元組根本不會送到這支程式。跟終端機和使用者設定搶鍵是打不贏的。
tmux set-hook -g after-resize-pane "send-keys -t $LPANE C-l"

# ── 狀態 ──────────────────────────────────────────────
QUERY=""
CUR=1
TOTAL=0
LAST_ID=""
DIRTY=1
W=0
H=0
PW=0
TOOSMALL=0
NEEDMEASURE=0

measure() {
    # 尺寸只在開始與 resize 時量。每次重畫都問 tmux 的話，
    # 光這幾次 round trip 就佔掉每鍵成本的一大塊。
    W=$(tmux display -p -t "$LPANE" '#{pane_width}')
    H=$(tmux display -p -t "$LPANE" '#{pane_height}')
    # 預覽窗格的寬度要傳給 md.awk，code block 的框線才畫得到右緣。
    # 寬度變了就得把 render 快取丟掉重畫，否則框線會停在舊寬度。
    npw=$(tmux display -p -t "${RPANE:-$LPANE}" '#{pane_width}' 2>/dev/null)
    if [ "${npw:-0}" != "$PW" ]; then
        PW=${npw:-0}
        rm -f "$CACHE"/* 2>/dev/null
        LAST_ID=""
    fi
}

refresh_items() {
    ab_items > "$ITEMS" 2>/dev/null || : > "$ITEMS"
    TOTAL=$(wc -l < "$ITEMS" | tr -d ' ')
    rm -f "$CACHE"/*
}

draw_list() {
    # 執行中的尺寸守門。
    # 同一個 session 只要有一個很小的 client 附著（例如某次 attach 留下的殭屍），
    # tmux 就會把整個 session 縮到最小的那個 —— 版面爛掉、resize hook 一直觸發，
    # 使用者看到的是「畫面一直在跳」。這裡改成印一次靜止的診斷就停手，不再重畫。
    if [ "$H" -lt 10 ] || [ "$W" -lt 40 ]; then
        if [ "$TOOSMALL" = 0 ]; then
            TOOSMALL=1
            printf '\033[H\033[2J'
            printf '視窗太小 %sx%s\r\n' "$W" "$H"
            printf '有小 client 附著？\r\n'
            printf 'tmux list-clients\r\n'
            printf 'tmux detach-client -t X\r\n'
        fi
        return
    fi
    if [ "$TOOSMALL" = 1 ]; then
        TOOSMALL=0
        LAST_ID=""          # 從小尺寸回來，預覽要重印
    fi

    : > "$MATCH"
    awk -v q="$QUERY" -v cur="$CUR" -v w="$W" -v h="$H" -v total="$TOTAL" \
        -v mf="$MATCH" -f "$DIR/list.awk" "$ITEMS"
}

selected_id() { sed -n "${CUR}p" "$MATCH" 2>/dev/null | cut -f1; }

draw_preview() {
    [ "$TOOSMALL" = 1 ] && return
    id=$(selected_id)
    [ -z "$id" ] && return
    [ "$id" = "$LAST_ID" ] && return       # 選中項沒變就不用重畫
    LAST_ID=$id

    f="$CACHE/${id#@}"
    # 每行結尾補 \033[K（清到行尾），這樣重畫時就不需要清整個畫面。
    # \033[2J 是肉眼可見的一閃，換頁面時特別明顯。
    [ -f "$f" ] || ab_prompt "$id" | awk -v w="$PW" -f "$DIR/md.awk" \
        | awk 'BEGIN { EL = sprintf("%c[K", 27) } { print $0 EL }' > "$f"

    # 先清 history 再寫，寫的時候用 \033[H 覆蓋而不是 \033[2J 清空 ——
    # 清整個畫面是肉眼看得到的一閃，換選項時會一直閃。
    # 覆蓋式重畫靠每行結尾的 \033[K 清掉舊字，最後再 \033[J 清掉底下殘留。
    # 內容超過一頁時照樣會捲進（剛清空的）history，history-top 仍然回得到頂端。
    #
    # tmux 指令用 \; 串起來一次送完，少幾次 round trip。
    tmux send-keys -t "$RPANE" -X cancel \; set-option -g "$K_CURSOR" "$id" 2>/dev/null
    tmux clear-history -t "$RPANE" 2>/dev/null
    { printf '\033[H'; cat "$f"; printf '\033[J'; } > "$FIFO"

    # 捲到頂：預設 pane 停在尾端，標題會看不到。
    # 捲動與折行都交給 tmux，它算得對（含 CJK），還附 [n/m] 指示器。
    tmux copy-mode -t "$RPANE" \; send-keys -t "$RPANE" -X history-top 2>/dev/null
}

scroll() { tmux send-keys -t "$RPANE" -X "$1" 2>/dev/null; }

# 刪除。自己畫確認提示，不用 tmux 的 confirm-before ——
# 那支需要一個明確的 target-client，從 pane 裡呼叫時解析不到（"no current client"）。
# 反正選單本來就掌握畫面與按鍵，自己問更單純，視覺也一致。
remove() {
    id=$(selected_id)
    [ -z "$id" ] && return
    name=$(tmux display -p -t "$id" '#{window_name}' 2>/dev/null)
    # 提示畫在最後一列。關掉自動換行，長標題不會把畫面頂掉。
    printf '\033[?7l\033[%d;1H\033[K\033[7m 刪除「%s」? y = 確定，其他鍵取消 \033[0m\033[?7h' \
        "$H" "$name"
    k=$(readbytes)
    set -- $k
    if [ "${1:-}" = 121 ] || [ "${1:-}" = 89 ]; then      # y / Y
        tmux kill-window -t "$id" 2>/dev/null
        refresh_items
        CUR=1
        LAST_ID=""
    fi
    DIRTY=1
}

dispatch() {
    id=$(selected_id)
    [ -z "$id" ] && return
    # 背景跑：dispatch 會等 claude 起來，最多 30 秒，不能卡住選單迴圈
    tmux run-shell -b "sh '$DIR/dispatch.sh' $id" 2>/dev/null
}

# 狀態輪替。狀態本身是任意字串（排版會自動對齊），這裡只是給人快速切換用。
cycle_status() {
    id=$(selected_id)
    [ -z "$id" ] && return
    cur=$(ab_items | awk -F"$US" -v w="$id" '$1==w {print $2; exit}')
    case $cur in
        pending) next=blocked ;;
        blocked) next=done ;;
        done)    next=pending ;;
        running) next=done ;;
        *)       next=pending ;;
    esac
    ab_set_status "$id" "$next"
    refresh_items
    DIRTY=1
}

# 調整中間分隔線。調完把寬度記到 global option，下次開起來一樣寬。
# 只負責改尺寸。量測與重畫交給主迴圈統一做 ——
# 連按 ⌥←→ 時每一步都重畫會閃到不行。
widen() {
    tmux resize-pane -t "$LPANE" "$1" 4 2>/dev/null
    NEEDMEASURE=1
}

clamp() {
    hit=$(wc -l < "$MATCH" | tr -d ' ')
    [ "$hit" -eq 0 ] && { CUR=1; return; }
    [ "$CUR" -lt 1 ] && CUR=1
    [ "$CUR" -gt "$hit" ] && CUR=$hit
}

# ── 讀鍵 ──────────────────────────────────────────────
# 一次讀「這一批」而不是一個位元組。
# tty 在 raw（min 1）模式下，一次 read() 會把當下已到達的位元組全部給你，
# 所以快打或貼上時只付一次 dd+od 的成本，方向鍵的 ESC [ A 三個位元組也會
# 一起到，不必為了辨識它去做逾時讀取。
readbytes() { dd bs=256 count=1 2>/dev/null | od -An -tu1; }

# 只有在 ESC 落在整批的最後一個位元組時才需要它 —— 分辨「單獨按 ESC」
# 與「序列被切成兩批送達」。
readbytes_timed() {
    stty min 0 time 1
    b=$(readbytes)
    stty min 1 time 0
    printf '%s' "$b"
}

append_char() {
    QUERY="$QUERY$(printf "\\$(printf '%03o' "$1")")"
    CUR=1; DIRTY=1
}

# 處理一整批位元組。$@ 是位元組值的序列。
process() {
    while [ $# -gt 0 ]; do
        n=$1; shift
        case $n in
            3)     finish ;;                                   # C-c
            13)    TARGET=$(selected_id); finish ;;            # Enter
            14)    CUR=$((CUR + 1)); clamp; DIRTY=1 ;;         # C-n
            16)    CUR=$((CUR - 1)); clamp; DIRTY=1 ;;         # C-p
            # 預覽捲動。Mac 鍵盤沒有實體 PageUp/PageDown（要按 Fn+↑↓），
            # 所以主推 Ctrl 系列；而且只長一點點的內容用整頁翻會直接跳到底，
            # 逐行與半頁才是實際會用的。
            6)     scroll page-down ;;                         # C-f 整頁
            2)     scroll page-up ;;                           # C-b 整頁
            4)     scroll halfpage-down ;;                     # C-d 半頁
            21)    scroll halfpage-up ;;                       # C-u 半頁
            5)     scroll scroll-down ;;                       # C-e 一行
            25)    scroll scroll-up ;;                         # C-y 一行
            # C-l：重畫。也是 client-resized 與 after-resize-pane 兩個 hook 的喚醒鍵。
            7)     dispatch ;;                                # C-g 派工
            20)    cycle_status ;;                            # C-t 切換狀態
            24)    remove ;;                                  # C-x 刪除（會先確認）
            # C-l：重畫。也是 client-resized / after-resize-pane 等 hook 的喚醒鍵。
            # 這裡只記旗標 —— 實際量測與重畫在主迴圈做，才有機會先把
            # 連續湧進來的 resize 事件吸收掉。
            12)    NEEDMEASURE=1 ;;
            18)    refresh_items; CUR=1; LAST_ID=""; DIRTY=1 ;;          # C-r
            127|8) QUERY=$(printf '%s' "$QUERY" | sed 's/.$//')
                   CUR=1; DIRTY=1 ;;
            27)
                # ESC 開頭。91 = '['（一般模式）、79 = 'O'（application cursor
                # mode，兩種都遇得到）。序列通常跟 ESC 同一批到達。
                if [ $# -eq 0 ]; then
                    # ESC 是這批的最後一個 —— 等一下下看有沒有後續
                    more=$(readbytes_timed)
                    [ -z "$more" ] && finish        # 真的是單獨的 ESC
                    set -- $more
                fi
                case ${1:-} in
                    # Option+← / Option+→。多數終端機把 Option 當 Meta，
                    # 送出的是 ESC b / ESC f，不是 CSI 序列。
                    # macOS 把 Ctrl+←→ 拿去切換桌面空間了，所以這組才是實際按得到的。
                    98)  shift; widen -L; continue ;;
                    102) shift; widen -R; continue ;;
                    91|79) shift ;;
                    # ESC 加上其他東西：整段丟掉。
                    # 不 shift 的話那個位元組會被當成一般輸入接進查詢字串。
                    *) [ $# -gt 0 ] && shift; continue ;;
                esac
                # 先把參數位元組（0-9 和 ;）收完，再看結尾字元是什麼。
                # 這樣才分得出「←」（ESC [ D）與「Ctrl+←」（ESC [ 1;5 D）。
                params=""
                while [ $# -gt 0 ]; do
                    case $1 in
                        48|49|50|51|52|53|54|55|56|57|59)
                            params="$params $1"; shift ;;
                        *) break ;;
                    esac
                done
                fin=${1:-}; [ $# -gt 0 ] && shift
                case $fin in
                    65) CUR=$((CUR - 1)); clamp; DIRTY=1 ;;    # ↑
                    66) CUR=$((CUR + 1)); clamp; DIRTY=1 ;;    # ↓
                    # 有修飾鍵的方向鍵：1;3 = Option、1;5 = Ctrl，兩種都收
                    67) [ -n "$params" ] && widen -R ;;        # ⌥/Ctrl + → 加寬
                    68) [ -n "$params" ] && widen -L ;;        # ⌥/Ctrl + ← 縮窄
                    126)
                        case $params in
                            *53*) scroll page-up ;;            # PageUp（5~）
                            *54*) scroll page-down ;;          # PageDown（6~）
                        esac ;;
                    *) : ;;
                esac
                ;;
            *)
                # 可見字元與 UTF-8 位元組都直接接上去。
                # 中文是 3 個位元組，比對走 index() 所以位元組層級是對的。
                [ "$n" -ge 32 ] && append_char "$n"
                ;;
        esac
    done
}

# ── 主迴圈 ────────────────────────────────────────────
measure
refresh_items
draw_list
draw_preview

stty raw -echo

eof=0
while :; do
    batch=$(readbytes)
    # 阻塞模式下讀到空的，通常代表 tty 已經沒了（EOF）。
    # 但也可能只是被訊號打斷（例如 SIGWINCH），所以連續幾次才認定。
    # 不做這個防護的話，tty 一消失就是無窮迴圈。
    if [ -z "$batch" ]; then
        eof=$((eof + 1))
        [ "$eof" -ge 50 ] && exit 0
        continue
    fi
    eof=0
    process $batch          # 不加引號：靠 IFS 切成一個個位元組值

    # resize 是連續事件 —— 拖曳分隔線、連按 ⌥←→、縮放終端機，
    # 每一步都會叫醒我們一次。每次都量測＋重畫的話會閃個不停。
    # 先等 100 ms 把後續吸收掉，安靜下來才量一次、畫一次。
    if [ "$NEEDMEASURE" = 1 ]; then
        while [ "$NEEDMEASURE" = 1 ]; do
            NEEDMEASURE=0
            stty min 0 time 1
            more=$(readbytes)
            stty min 1 time 0
            [ -n "$more" ] && process $more
        done
        measure
        [ "${W:-0}" -gt 0 ] && tmux set-option -g "$K_WIDTH" "$W" 2>/dev/null
        LAST_ID=""          # tmux 不會重排已印出的內容，預覽一定要重印
        DIRTY=1
    fi

    if [ "$DIRTY" = 1 ]; then
        draw_list
        draw_preview
        DIRTY=0
    fi
done
