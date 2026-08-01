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
STTY_SAVE=$(stty -g)
RPANE=""
TARGET=""

# ── 收尾 ──────────────────────────────────────────────
# raw 模式沒還原的話，離開後終端機是廢的，所以 trap 從第一天就要有。
cleanup() {
    stty "$STTY_SAVE" 2>/dev/null
    for _hk in client-resized client-attached client-detached after-resize-pane; do
        tmux set-hook -gu "$_hk" 2>/dev/null
    done
    rm -rf "$TMP"
}
# HUP 一定要攔：tmux kill-window 送的就是 SIGHUP，漏掉的話收尾完全不會跑
# （實測後果：/tmp/ab.* 一直累積、client-resized hook 留著指向死掉的 pane）
trap cleanup EXIT INT TERM HUP QUIT

finish() {
    cleanup
    trap - EXIT
    # 沒有選任何東西（ESC / C-c）就回到開選單之前那個 window。
    # 不這樣做的話，殺掉自己之後 tmux 會自己挑一個，使用者會莫名掉在某則待辦的
    # shell 裡 —— 那個 shell 的提示字元跟原本的環境不一樣，看起來像換了台機器。
    [ -z "$TARGET" ] && TARGET=$(tmux show-options -gqv "$K_RETURN" 2>/dev/null)
    # 先把焦點移到目標 window，再殺掉自己這個 window。
    # 反過來做的話，殺掉 active window 會讓 tmux 自己挑下一個，蓋掉我們的選擇。
    [ -n "$TARGET" ] && tmux select-window -t "$TARGET" 2>/dev/null
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
TOOSMALL=0

measure() {
    # 尺寸只在開始與 resize 時量。每次重畫都問 tmux 的話，
    # 光這兩次 round trip 就佔掉每鍵成本的一大塊。
    W=$(tmux display -p -t "$LPANE" '#{pane_width}')
    H=$(tmux display -p -t "$LPANE" '#{pane_height}')
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
    [ -f "$f" ] || ab_prompt "$id" | awk -f "$DIR/md.awk" > "$f"

    # 順序有講究：先清畫面，再清 history，最後才寫新內容。
    # 反過來（先清 history 再寫）的話，新內容會把舊畫面「推」進 history，
    # 捲到頂看到的是上一則的尾巴，不是這一則的標題。
    #
    # tmux 指令用 \; 串起來一次送完，少幾次 round trip。
    tmux send-keys -t "$RPANE" -X cancel \; set-option -g "$K_CURSOR" "$id" 2>/dev/null
    printf '\033[H\033[2J' > "$FIFO"
    tmux clear-history -t "$RPANE" 2>/dev/null
    cat "$f" > "$FIFO"

    # 捲到頂：預設 pane 停在尾端，標題會看不到。
    # 捲動與折行都交給 tmux，它算得對（含 CJK），還附 [n/m] 指示器。
    tmux copy-mode -t "$RPANE" \; send-keys -t "$RPANE" -X history-top 2>/dev/null
}

scroll() { tmux send-keys -t "$RPANE" -X "$1" 2>/dev/null; }

# 調整中間分隔線。調完把寬度記到 global option，下次開起來一樣寬。
widen() {
    tmux resize-pane -t "$LPANE" "$1" 4 2>/dev/null
    measure
    tmux set-option -g "$K_WIDTH" "$W" 2>/dev/null
    LAST_ID=""          # 預覽也要跟著重印，因為 tmux 不會重排已印出的內容
    DIRTY=1
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
            12)    measure
                   tmux set-option -g "$K_WIDTH" "$W" 2>/dev/null   # 記住調過的寬度
                   LAST_ID=""      # tmux 不會重排已印出的內容，預覽要重印
                   DIRTY=1 ;;
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

while :; do
    batch=$(readbytes)
    [ -z "$batch" ] && continue
    process $batch          # 不加引號：靠 IFS 切成一個個位元組值

    if [ "$DIRTY" = 1 ]; then
        draw_list
        draw_preview
        DIRTY=0
    fi
done
