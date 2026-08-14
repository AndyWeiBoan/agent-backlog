#!/bin/sh
# agent-backlog 的 MCP server（stdio transport），零依賴。
#
# 存在的理由跟功能無關：同樣的事用 shell script 就做得到，但**新的 Claude Code
# session 不會知道那些 script 存在**。註冊成 MCP 之後每個 session 啟動就載入
# tool 與說明，agent 自己就知道有這份清單、知道能派工。買的是「可發現性」。
#
# 協定：換行分隔的 JSON-RPC 2.0。一行進、一行出。
# JSON 產生很單純（跳脫規則固定、非 ASCII 原樣輸出）；
# 解析交給 mcp/json_get.awk，它只認我們要的那幾個路徑。
#
# ⚠️ stdout 只能有 JSON-RPC 訊息，任何除錯輸出都要走 stderr。

set -u
DIR=$(cd "$(dirname "$0")" && pwd)
. "$DIR/lib.sh"
MCP="$DIR/mcp"
PROTOCOL=2025-06-18

# 這支是被主 Claude Code 啟動的，會繼承它的 TMUX_PANE —— 反查得到它在哪個 session。
# 這件事很重要：@agent_backlog_scope 預設是 session，人只看得到自己 session 的待辦；
# agent 這側如果不跟著 scope，人看到 0 則、agent 看到 11 則，
# 就違反了「人和 agent 看同一份」這個第一原則。
# 推不出來（例如 Claude Code 不是在 tmux 裡跑）就退回全域。
AB_SESSION=""
if [ -n "${TMUX_PANE:-}" ]; then
    AB_SESSION=$(tmux display -p -t "$TMUX_PANE" '#{session_id}' 2>/dev/null)
fi

TMP=$(mktemp -d /tmp/ab-mcp.XXXXXX)
trap 'rm -rf "$TMP"' EXIT INT TERM HUP QUIT
FIELDS="$TMP/fields"
BUF="$TMP/buf"

# ── JSON 小工具 ───────────────────────────────────────
esc() { awk -f "$MCP/json_str.awk"; }              # stdin → 跳脫後的字串內容
escs() { printf '%s' "$1" | esc; }                 # 單一參數版

# ── 回應 ──────────────────────────────────────────────
reply() { printf '{"jsonrpc":"2.0","id":%s,%s}\n' "$1" "$2"; }

reply_text() {                                     # $1=id $2=內容檔 $3=isError
    printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"' "$1"
    esc < "$2"
    printf '"}]%s}}\n' "$([ "${3:-}" = 1 ] && printf ',"isError":true')"
}

reply_err() {                                      # $1=id $2=code $3=訊息
    printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%s,"message":"%s"}}\n' \
        "$1" "$2" "$(escs "$3")"
}

INSTRUCTIONS='共享的待辦清單。使用者與 agent 看到同一份。

一則待辦 = 一個 tmux window：window 名稱是標題，內容存在 window 的
@agent_backlog_prompt 上。因此「待辦」與「執行它的地方」是同一個物件，
沒有兩份狀態要同步。

這不是 Claude Code 內建的 TodoWrite。內建那份是單一 session 內的步驟追蹤；
這份是使用者也看得到、可以派給其他 Claude Code 實例執行、
而且使用者能 attach 進去接手的工作項目。

典型用法：討論中冒出「這件事該做」時用 add 記下來；主 agent 用 list 掌握全局，
決定哪些自己做、哪些用 dispatch 派給獨立實例；用 peek 看派出去的進度。

## 待辦的內容是給人看的，不是 log

使用者會用眼睛掃這塊板子來決定「接下來做什麼」。所以每一則的判準只有一個：
**打開它，一眼看得出現在的狀態和下一步。**

寫入之前先問三件事：

1. 這件事已經在內容裡了嗎？是的話什麼都不要做。
2. 能不能用 check 打勾表示？能的話用 check，不要 append 一句「已完成 X」。
3. 這段文字會改變使用者的決定嗎？不會的話不要寫。

不要把 append 當成進度回報。「我讀了 A」「我試了 B 但失敗」「接著我看 C」
這類過程敘述對使用者沒有價值 —— 他要的是結論、還沒解的問題、以及下一步。
過程要看的話他會直接 attach 進那個 window，或用 peek。

## 長度：以一個畫面為目標

捲動就是在跟記憶借東西 —— 捲到第二頁時，第一頁已經要靠記住了。
所以長度不是美觀問題，是「使用者能不能一眼決定」的問題。

- 目標 **40 行以內**（大約一個畫面）
- **超過 80 行就不要再 append**。改成回報「這則已經 N 行，建議拆成 X 和 Y」，
  或指出前面哪一段已經過期，讓使用者決定怎麼處理
- 不確定現在多長就先用 show 看一眼，不要憑印象追加
- 純參考資料（對照表、查表）可以長，但標題要看得出那是參考、不是待辦

## 怎麼寫才讀得下去

1. **前三行就回答「現在什麼狀態、下一步做什麼」。** 結論在前，脈絡在後 ——
   使用者掃到這則時先看到的是開頭，不是結尾
2. **用 ## 小標分段。** 一段連續文字超過五行就該拆
3. **可執行的步驟一律寫成 - [ ]**，之後用 check 原地打勾 —— 那不會把這則撐長
4. **一行一個意思。** 條列優於句子，短句優於長句
5. **log 與程式碼只貼會影響判斷的那幾行。** 貼一百行 stack trace 是把線索埋起來
6. **過期的內容不能刪，但要明講。** 在後面寫「以上第 2 節已不成立，因為 X」，
   不要留著讓使用者自己比對

⚠️ 內容只能追加，不能改寫也不能刪段落。正因為亂掉之後救不回來，
寫進去之前要更克制 —— 少寫一句永遠比多寫一句安全。'

# 工具定義。
#
# description 不只是說明「這支做什麼」，也是唯一能約束 agent 怎麼用它的地方 ——
# 這裡沒有權限系統，也沒有 review 步驟。所以寫入類的工具（add / append / check /
# delete）都在 description 裡明講「什麼時候不要用」，而不只是「怎麼用」。
#
# 特別是 append：它是唯一會讓待辦「無限變長」的操作，而內容不能改寫。
# agent 拿它當進度回報用的話，那則很快就變成流水帳，使用者反而看不到重點。
tools_json() {
    cat <<'JSON'
[
{"name":"list","description":"列出全部待辦：id / 狀態 / 標題 / 該 window 目前跑什麼程式。「裡面在跑」是 tmux 直接回報的現實（shell = 還沒開始），不是記錄值。統籌分配前先看這個。","inputSchema":{"type":"object","properties":{}}},
{"name":"show","description":"讀某一則的完整內容。target 可以是標題或 window_id（@數字）。","inputSchema":{"type":"object","properties":{"target":{"type":"string","description":"標題或 window_id"}},"required":["target"]}},
{"name":"add","description":"新增一則待辦。建立 detached window 並存內容，不會啟動 claude。\n\nbody 有兩個讀者：使用者會用眼睛看它決定要不要做，而 dispatch 時它就是原封不動送給獨立 agent 的 prompt。所以寫的時候當成「交接單」——現象、已知的線索、要達成什麼、可以驗收的條件。把可打勾的步驟寫成 - [ ] checklist，之後就能用 check 原地更新進度，不必 append。\n\n內容只能追加不能改寫，所以一開始的結構會跟著這則一輩子。寧可先寫得精簡，需要再補。\n\n長度目標 40 行以內（大約使用者的一個畫面）。寫法：前三行先回答「現在什麼狀態、下一步做什麼」，之後才是脈絡；用 ## 小標分段，一段連續文字不超過五行；一行一個意思；log 與程式碼只貼會影響判斷的那幾行。","inputSchema":{"type":"object","properties":{"title":{"type":"string","description":"標題，會成為 window 名稱。清單同分時照標題排序，所以編號式命名（K0 K1 K2）會自然排對"},"body":{"type":"string","description":"內容（markdown）。派工時直接當 prompt。可打勾的步驟寫成 - [ ]。目標 40 行以內，結論寫在最前面"},"priority":{"type":"number","description":"優先度 1..10，越大越先做。省略 = 1"}},"required":["title","body"]}},
{"name":"dispatch","description":"派工：在該 window 啟動獨立的 claude 實例並把內容送進去，狀態轉 running。使用者可以 attach 進去接手。","inputSchema":{"type":"object","properties":{"target":{"type":"string","description":"標題或 window_id"}},"required":["target"]}},
{"name":"peek","description":"capture 該 window 目前的畫面，用來看派出去的進度。","inputSchema":{"type":"object","properties":{"target":{"type":"string","description":"標題或 window_id"}},"required":["target"]}},
{"name":"check","description":"把某一則裡的 checklist 項目打勾／取消打勾。用 index（第幾個 checkbox，1 起算）或 match（子字串）指定哪一個。刻意做成窄工具：只會換 [ ] 與 [x]，不會動到任何其他文字 —— 這個系統沒有 undo。\n\n這是回報進度的首選方式，優先於 append。做完一項就打勾，不要另外 append 一句「已完成 X」——打勾是原地更新，不會把那則撐長；append 會，而且兩邊講同一件事之後使用者還得自己對照。內容裡沒有對應的 checklist 項目時才考慮 append。","inputSchema":{"type":"object","properties":{"target":{"type":"string","description":"標題或 window_id"},"index":{"type":"number","description":"第幾個 checkbox，1 起算"},"match":{"type":"string","description":"用子字串找那一項（沒給 index 時用）"},"done":{"type":"boolean","description":"true = 打勾（預設），false = 取消"}},"required":["target"]}},
{"name":"append","description":"在某一則的內容尾端追加一段 markdown。刻意只能追加不能覆寫，所以每一次呼叫都是不可逆的——那則會永遠變長一點，而使用者是用眼睛掃這塊板子的。\n\n用之前先確認三件事：(1) 這件事已經寫在內容裡了嗎？是的話不要重複；(2) 能不能改用 check 打勾表示？能的話用 check，不要 append 一句「已完成 X」；(3) 這段會改變使用者的決定嗎？不會就不要寫。\n\n不要拿它做進度回報。「我讀了 A」「我試了 B 但失敗」「接下來看 C」這種過程敘述請不要寫進來——使用者要看過程會自己 attach 進那個 window 或用 peek。該寫的是：結論、還沒解的問題、以及下一步。\n\n寫的時候給結構：一個 ## 小標題起頭，底下用條列，不要一整段散文。一行一個意思，一段連續文字不超過五行。一次寫完，不要拆成好幾次呼叫慢慢加——那會讓那則變成一條流水帳。\n\n先估長度再決定要不要寫。使用者的一個畫面大約 40 行；不確定這則現在多長就先用 show 看一眼。加完之後會超過 80 行的話就不要 append——改成回報「這則已經 N 行，建議拆成 X 和 Y」，或指出前面哪一段已經過期，讓使用者決定。內容不能改寫，所以救不回來的是他，不是你。","inputSchema":{"type":"object","properties":{"target":{"type":"string","description":"標題或 window_id"},"text":{"type":"string","description":"要追加的 markdown。有結構、精簡、只寫會影響決定的東西。加完之後整則不該超過 80 行"}},"required":["target","text"]}},
{"name":"set_status","description":"更新狀態。任意字串，慣例是 pending / running / blocked / done。標成 done 之後那一則會自動沉到清單底部。","inputSchema":{"type":"object","properties":{"target":{"type":"string","description":"標題或 window_id"},"status":{"type":"string"}},"required":["target","status"]}},
{"name":"set_priority","description":"設定優先度，1..10，越大越先做，預設 1。清單（人看到的和 list 回的）都照這個排序，所以這是「讓某件事浮到最上面」的方法。超出範圍會被夾住。","inputSchema":{"type":"object","properties":{"target":{"type":"string","description":"標題或 window_id"},"priority":{"type":"number","description":"1..10"}},"required":["target","priority"]}},
{"name":"delete","description":"刪掉一則待辦（會關掉它的 tmux window）。一次只能刪一則，必須指名 target —— 沒有批次、沒有清空。刪之前整則會被塞進 tmux buffer agent_backlog_deleted，所以手滑還有一次機會救（tmux show-buffer -b agent_backlog_deleted）。如果那個 window 裡有東西在跑（包含被 dispatch 出去、正在工作的 claude），會被拒絕 —— 那要先確認它真的可以砍，再用 force。這個系統沒有 undo，所以除非使用者要你刪，不要主動刪；不確定該不該留的話用 set_status 標成 done，讓使用者自己決定。","inputSchema":{"type":"object","properties":{"target":{"type":"string","description":"標題或 window_id。不接受萬用字元，一次一則"},"force":{"type":"boolean","description":"true = 連「裡面有東西在跑」也照樣刪。會殺掉那個 pane 裡的行程"}},"required":["target"]}}
]
JSON
}

# ── 把 target（標題或 window_id）解析成 window_id ─────
resolve() {
    case $1 in
        @*) printf '%s' "$1"; return ;;
    esac
    ab_items | awk -F'\t' -v n="$1" '$3==n {print $1; exit}'
}

have_server() { tmux list-sessions >/dev/null 2>&1; }

# ── 主迴圈 ────────────────────────────────────────────
while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf '%s\n' "$line" | awk -f "$MCP/json_get.awk" > "$FIELDS"
    get() { awk -F'\t' -v k="$1" '$1==k {sub(/^[^\t]*\t/, ""); print; exit}' "$FIELDS"; }

    id=$(get .id)
    method=$(get .method)

    # 通知（沒有 id）不回應
    if [ -z "$id" ]; then
        continue
    fi

    case $method in
        initialize)
            printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"%s","capabilities":{"tools":{}},"serverInfo":{"name":"agent-backlog","version":"0.1.0"},"instructions":"' \
                "$id" "$PROTOCOL"
            printf '%s' "$INSTRUCTIONS" | esc
            printf '"}}\n'
            ;;
        ping)
            reply "$id" '"result":{}'
            ;;
        tools/list)
            printf '{"jsonrpc":"2.0","id":%s,"result":{"tools":%s}}\n' \
                "$id" "$(tools_json | tr -d '\n')"
            ;;
        tools/call)
            name=$(get .params.name)
            if ! have_server; then
                printf '%s' "agent-backlog: tmux server 沒有在執行。待辦存在 tmux window 上，請先啟動 tmux。" > "$BUF"
                reply_text "$id" "$BUF" 1
                continue
            fi
            case $name in
                list)
                    if [ -z "$(ab_items)" ]; then
                        printf '%s' "目前沒有待辦。" > "$BUF"
                    else
                        # 不要用 `read` 切 tab 分隔的欄位 —— tab 屬於 IFS whitespace，
                        # 連續兩個會被併成一個，空的狀態欄會讓整排跑位。用 awk 切。
                        # 順便把 pane_current_command 一起在 tmux 那邊取回來，省掉逐則查詢。
                        # 清單是整個 server 的，待辦可能散在不同 session ——
                        # 標出來 agent 才知道 dispatch 之後人要去哪裡找。
                        if [ "$AB_SCOPE" = session ] && [ -n "$AB_SESSION" ]; then
                            _t="-t $AB_SESSION"
                        else
                            _t="-a"
                        fi
                        # shellcheck disable=SC2086
                        # 欄位順序要跟 sort.awk 的前四欄對上（id / 狀態 / 標題 /
                        # 優先度），後面掛的東西它會原樣帶過去。
                        # 排序走同一支，所以 agent 看到的順序跟人看到的一樣。
                        tmux list-windows $_t -f "$AB_FILTER" \
                            -F "#{window_id}${US}${AB_STATUS_F}${US}#{window_name}${US}#{$K_PRIORITY}${US}#{pane_current_command}${US}#{session_name}" \
                        | LC_ALL=C awk -f "$DIR/sort.awk" \
                        | awk -F"$US" '{printf "%s  p%-2s %-8s %s  [%s]  (%s)\n", $1, $4, ($2==""?"-":$2), $3, $6, $5}' \
                            > "$BUF"
                    fi
                    reply_text "$id" "$BUF"
                    ;;
                show)
                    wid=$(resolve "$(get .params.arguments.target)")
                    if [ -z "$wid" ]; then
                        printf '找不到：%s' "$(get .params.arguments.target)" > "$BUF"
                        reply_text "$id" "$BUF" 1
                    else
                        ab_prompt "$wid" > "$BUF"
                        reply_text "$id" "$BUF"
                    fi
                    ;;
                add)
                    title=$(get .params.arguments.title)
                    # body 裡的換行在解析時被壓成字面的 \n，這裡還原回真的換行
                    get .params.arguments.body | awk '{gsub(/\\n/, "\n"); print}' > "$TMP/body"
                    # 建在 agent 自己所在的 session —— 不指定的話會落在「當前
                    # session」，那不一定是使用者那個，session scope 下他就看不到。
                    if [ -n "$AB_SESSION" ]; then
                        wid=$(tmux new-window -d -t "$AB_SESSION" -n "$title" -P -F '#{window_id}')
                    else
                        wid=$(tmux new-window -d -n "$title" -P -F '#{window_id}')
                    fi
                    tmux set-option -w -t "$wid" "$K_PROMPT" "$(cat "$TMP/body")"
                    tmux set-option -w -t "$wid" "$K_STATUS" pending
                    # 優先度選填。JSON number 可能帶小數點（3.0），先切掉。
                    pr=$(get .params.arguments.priority | cut -d. -f1)
                    if [ -n "$pr" ]; then
                        ab_set_priority "$wid" "$pr"      # 裡面會同步 window 順序
                    else
                        ab_sync_order "$(ab_session_of "$wid")"
                    fi
                    printf '已新增 %s（%s）' "$title" "$wid" > "$BUF"
                    reply_text "$id" "$BUF"
                    ;;
                dispatch)
                    wid=$(resolve "$(get .params.arguments.target)")
                    if [ -z "$wid" ]; then
                        printf '找不到：%s' "$(get .params.arguments.target)" > "$BUF"
                        reply_text "$id" "$BUF" 1
                    else
                        sh "$DIR/dispatch.sh" "$wid" >/dev/null 2>&1 &
                        printf '已派工給 %s。用 peek 看進度。' "$wid" > "$BUF"
                        reply_text "$id" "$BUF"
                    fi
                    ;;
                peek)
                    wid=$(resolve "$(get .params.arguments.target)")
                    if [ -z "$wid" ]; then
                        printf '找不到：%s' "$(get .params.arguments.target)" > "$BUF"
                        reply_text "$id" "$BUF" 1
                    else
                        tmux capture-pane -pt "$wid" > "$BUF" 2>/dev/null
                        reply_text "$id" "$BUF"
                    fi
                    ;;
                check)
                    wid=$(resolve "$(get .params.arguments.target)")
                    if [ -z "$wid" ]; then
                        printf '找不到：%s' "$(get .params.arguments.target)" > "$BUF"
                        reply_text "$id" "$BUF" 1
                    else
                        _idx=$(get .params.arguments.index)
                        _mt=$(get .params.arguments.match)
                        _dn=$(get .params.arguments.done)
                        [ "$_dn" = false ] && _dn=0 || _dn=1
                        ab_prompt "$wid" > "$TMP/body"
                        awk -v idx="${_idx:-0}" -v match_="$_mt" -v done_="$_dn" \
                            -v rf="$TMP/res" -f "$MCP/check.awk" "$TMP/body" > "$TMP/new"
                        if [ "$(cut -f1 "$TMP/res")" = 1 ]; then
                            tmux set-option -w -t "$wid" "$K_PROMPT" "$(cat "$TMP/new")"
                            printf '已更新：%s' "$(cut -f2 "$TMP/res")" > "$BUF"
                            reply_text "$id" "$BUF"
                        else
                            printf '找不到符合的 checklist 項目（index=%s match=%s）' \
                                "${_idx:-—}" "${_mt:-—}" > "$BUF"
                            reply_text "$id" "$BUF" 1
                        fi
                    fi
                    ;;
                append)
                    wid=$(resolve "$(get .params.arguments.target)")
                    if [ -z "$wid" ]; then
                        printf '找不到：%s' "$(get .params.arguments.target)" > "$BUF"
                        reply_text "$id" "$BUF" 1
                    else
                        ab_prompt "$wid" > "$TMP/body"
                        printf '\n' >> "$TMP/body"
                        get .params.arguments.text \
                            | awk '{gsub(/\\n/, "\n"); print}' >> "$TMP/body"
                        tmux set-option -w -t "$wid" "$K_PROMPT" "$(cat "$TMP/body")"
                        printf '已追加到 %s' "$wid" > "$BUF"
                        reply_text "$id" "$BUF"
                    fi
                    ;;
                set_status)
                    wid=$(resolve "$(get .params.arguments.target)")
                    st=$(get .params.arguments.status)
                    if [ -z "$wid" ]; then
                        printf '找不到：%s' "$(get .params.arguments.target)" > "$BUF"
                        reply_text "$id" "$BUF" 1
                    else
                        ab_set_status "$wid" "$st"
                        printf '%s 狀態改為 %s' "$wid" "$st" > "$BUF"
                        reply_text "$id" "$BUF"
                    fi
                    ;;
                set_priority)
                    wid=$(resolve "$(get .params.arguments.target)")
                    # JSON number 可能是 7.0，cut 掉小數部分
                    pr=$(get .params.arguments.priority | cut -d. -f1)
                    if [ -z "$wid" ]; then
                        printf '找不到：%s' "$(get .params.arguments.target)" > "$BUF"
                        reply_text "$id" "$BUF" 1
                    else
                        ab_set_priority "$wid" "$pr"
                        # 回報夾過之後的實際值，agent 才知道 99 沒有生效
                        printf '%s 優先度改為 %s' "$wid" \
                            "$(tmux show-options -w -qv -t "$wid" "$K_PRIORITY")" > "$BUF"
                        reply_text "$id" "$BUF"
                    fi
                    ;;
                delete)
                    wid=$(resolve "$(get .params.arguments.target)")
                    force=$(get .params.arguments.force)
                    if [ -z "$wid" ]; then
                        printf '找不到：%s' "$(get .params.arguments.target)" > "$BUF"
                        reply_text "$id" "$BUF" 1
                    elif [ "$force" != true ] && ! ab_is_idle "$wid"; then
                        # 擋下來而不是砍掉。那個 pane 裡跑的可能是 dispatch 出去、
                        # 正在工作的 claude，也可能是使用者自己開的 vim。
                        printf '%s 裡面有東西在跑（%s），沒有刪。\n真的要刪就帶 force: true——那會殺掉那個行程。' \
                            "$wid" "$(tmux display -p -t "$wid" '#{pane_current_command}' 2>/dev/null)" > "$BUF"
                        reply_text "$id" "$BUF" 1
                    else
                        wname=$(tmux display -p -t "$wid" '#{window_name}' 2>/dev/null)
                        wsess=$(ab_session_of "$wid")
                        ab_stash "$wid"                 # 刪之前留最後一份副本
                        tmux kill-window -t "$wid" 2>/dev/null
                        ab_sync_order "$wsess"
                        printf '已刪除 %s（%s）。內容還在 tmux buffer %s，要救回來：\n  tmux show-buffer -b %s > /tmp/x && sh scripts/restore.sh /tmp/x' \
                            "$wname" "$wid" "$AB_STASH_BUF" "$AB_STASH_BUF" > "$BUF"
                        reply_text "$id" "$BUF"
                    fi
                    ;;
                *)
                    reply_err "$id" -32602 "沒有這個工具：$name"
                    ;;
            esac
            ;;
        *)
            reply_err "$id" -32601 "不支援的方法：$method"
            ;;
    esac
done
