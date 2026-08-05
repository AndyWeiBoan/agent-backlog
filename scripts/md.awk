# 極簡 markdown → ANSI renderer（POSIX awk，零外部依賴）
# 原型：證明純 tmux plugin 也能自己做 render 與語法高亮。
#
# 刻意不做「換行」—— 內容是印進 pane 的，終端機自己會按顯示寬度折行，算得比我們對
# （含 CJK），還附 [n/m] 指示器。程式碼區塊用左側 │ 邊框而不是滿版底色，也不必補寬度。
#
# 表格是唯一必須自己算顯示寬度的地方：欄要對齊就得知道每個 cell 佔幾格。
# 寬度計算在 width.awk（list.awk 也用同一份），連同它的兩個坑一起寫在那裡。
#
# ⚠️ 呼叫方式是兩個 -f，而且要 LC_ALL=C：
#     LC_ALL=C awk -f width.awk -f md.awk

BEGIN {
    E   = sprintf("%c[", 27)
    R   = E "0m"          # reset
    B   = E "1m"          # bold
    # ~~刪除線~~。dim 是刻意加的 fallback：SGR 9 有些終端機不畫
    # （macOS 內建的 Terminal.app 就是），那時候至少還會變暗，
    # 而不是跟一般文字完全一樣。tmux 3.4 與 3.6a 都會原樣傳出去（實測過）。
    STRIKE = E "2;9m"
    DIM = E "2m"
    # 256 色
    H1  = E "1;38;5;39m"  # 標題一：亮藍
    H2  = E "1;38;5;42m"  # 標題二：綠
    H3  = E "1;38;5;214m" # 標題三：橘
    BUL = E "38;5;214m"   # bullet 符號
    COD = E "38;5;231;48;5;236m"  # inline code：淺字深底
    # 表格 cell 裡的 inline code 只上前景色，不要底色也不要補空格。
    # 理由：表格本身已經是結構化的，再加一塊底色是雙重編碼，會把欄位切碎；
    # 而且補的空格會算進顯示寬度，對齊就毀了。
    COD_T = E "38;5;153m"
    # 表格的斑馬紋（zebra striping）底色。
    # 用 236 是因為 inline code 的底色本來就是 236 —— 同一個顏色已經在這個
    # renderer 裡驗過能看，不需要再賭第二個色號在別人的配色下長怎樣。
    ZEB = E "48;5;236m"
    BAR = E "38;5;240m"   # 邊框
    QUO = E "38;5;108m"   # 引用
    TODO = E "38;5;214m"  # 未打勾的框
    DONE = E "38;5;42m"   # 打勾的框

    # 語法高亮用的色
    KW  = E "38;5;81m"    # 關鍵字
    STR = E "38;5;186m"   # 字串
    NUM = E "38;5;141m"   # 數字
    CMT = E "38;5;244m"   # 註解

    # 關鍵字表：查表用大寫，所以 SQL 的大小寫寫法都吃得到
    sqlkw = "SELECT FROM WHERE AND OR NOT NULL INNER LEFT RIGHT OUTER JOIN ON GROUP ORDER BY HAVING AS SUM COUNT COALESCE DISTINCT INSERT INTO VALUES UPDATE SET DELETE CREATE INDEX TABLE LIMIT OFFSET CASE WHEN THEN ELSE END WITH UNION ALL IS IN EXISTS"
    cskw  = "PUBLIC PRIVATE PROTECTED INTERNAL SEALED CLASS INTERFACE RECORD STRUCT VAR AWAIT ASYNC RETURN NEW IF ELSE FOREACH FOR WHILE THROW TRY CATCH FINALLY USING NAMESPACE STATIC READONLY CONST TRUE FALSE NULL THIS BASE VOID TASK"
    # 框線要畫到多寬。由呼叫端把預覽窗格的寬度傳進來（-v w=...）。
    # 沒傳就給一個保守值 —— 寧可短，也不要換行造成階梯狀的破框。
    if (w + 0 < 8) w = 56
    n = split(sqlkw, a, " "); for (i = 1; i <= n; i++) { KWSET["sql|" a[i]] = 1 }
    n = split(cskw,  a, " "); for (i = 1; i <= n; i++) { KWSET["cs|"  a[i]] = 1 }
    fence = 0

    nt = 0            # 手上有沒有正在累積的表格
    tnr = 0; tnc = 0  # 表格的列數 / 欄數
}

# ── 表格 ─────────────────────────────────────────────────────
#
# 表格必須整塊看完才知道每欄要多寬，所以先累積，遇到第一行非表格的行再吐出來。
# 這條規則要放在 fence 之前 —— 表格後面緊接 ``` 時，要先把表格印完。
nt > 0 && fence == 0 && $0 !~ /^[ \t]*\|/ { tflush() }

# ── 程式碼區塊 ───────────────────────────────────────────────
/^```/ {
    if (fence == 0) {
        fence = 1
        lang = substr($0, 4)
        gsub(/[ \t]+$/, "", lang)
        # 圖表：整塊收起來，收完再決定畫成圖還是畫成程式碼。
        # 不能邊讀邊畫，因為「認不認得」要看完整塊才知道。
        if (lang ~ /^(mermaid|plantuml|puml|uml)$/) { dia = 1; dn = 0; next }
        # 上框：┌─ lang ──────…── 一路畫到窗格右緣。
        # 原本這裡是寫死的五個「─」，看起來像畫到一半沒收尾。
        head = (lang == "" ? "" : " " lang " ")
        printf "%s┌─%s%s%s\n", BAR,
               (lang == "" ? "" : " " B lang R BAR " "),
               dash(w - 2 - dw(head)), R
    } else {
        fence = 0
        if (dia) {
            dia = 0
            # 兩支各試一次，第一個認得的贏。不認得就回 ""。
            # 順序無所謂 —— sequenceDiagram 與 flowchart 的開頭關鍵字互斥。
            #
            # 曾經也支援 erDiagram 與 C4Context，後來拿掉了 ——
            # 範圍收在「時序圖 + 流程圖」。認不出來的一律退回 code block，
            # 所以拿掉之後那兩種語法就變回顯示原始碼，不會壞。
            diaout = seq_render(DIA, dn)
            if (diaout == "") diaout = flow_render(DIA, dn)
            if (diaout != "") { printf "%s", diaout; next }
            # 認不出來（flowchart 之類）就退回 code block ——
            # 最壞情況是看到原始碼，跟沒有這個功能時一模一樣。
            printf "%s┌─%s%s%s\n", BAR, " " B lang R BAR " ", dash(w - 4 - dw(lang)), R
            for (di = 1; di <= dn; di++) printf "%s│%s %s\n", BAR, R, DIA[di]
            printf "%s└%s%s\n", BAR, dash(w - 1), R
            next
        }
        printf "%s└%s%s\n", BAR, dash(w - 1), R
    }
    next
}
fence == 1 && dia == 1 { DIA[++dn] = $0; next }
fence == 1 {
    printf "%s│%s %s\n", BAR, R, highlight($0, lang)
    next
}

# 累積一列。放在 fence 規則之後，程式碼區塊裡的 | 才不會被當成表格。
fence == 0 && /^[ \t]*\|/ {
    tline = $0
    sub(/^[ \t]*\|/, "", tline)
    sub(/\|[ \t]*$/, "", tline)
    tm = split(tline, tc, "|")

    # 分隔列（|---|:--:|---:|）不是資料，它宣告的是對齊方式
    isdelim = (tm > 0)
    for (ti = 1; ti <= tm; ti++) {
        gsub(/^[ \t]+/, "", tc[ti]); gsub(/[ \t]+$/, "", tc[ti])
        if (tc[ti] !~ /^:?-+:?$/) isdelim = 0
    }
    if (isdelim) {
        for (ti = 1; ti <= tm; ti++) {
            if (tc[ti] ~ /^:-+:$/)    TA[ti] = "c"
            else if (tc[ti] ~ /-+:$/) TA[ti] = "r"
            else                      TA[ti] = "l"
        }
        nt = 1          # 只有表頭 + 分隔列時也還算一個表格
        next
    }

    tnr++; nt = 1
    if (tm > tnc) tnc = tm
    for (ti = 1; ti <= tm; ti++) {
        T[tnr, ti] = tc[ti]
        tw_ = dw(tplain(tc[ti]))
        if (tw_ > TW[ti]) TW[ti] = tw_
    }
    next
}

# ── 標題 ─────────────────────────────────────────────────────
/^### / { printf "%s▸ %s%s\n", H3, substr($0, 5), R; next }
/^## /  { printf "\n%s┃ %s%s\n", H2, substr($0, 4), R; next }
/^# /   { printf "\n%s█ %s%s\n", H1, substr($0, 3), R; next }

# ── 水平線 ───────────────────────────────────────────────────
/^---+$/ { printf "%s%s%s\n", BAR, dash(w), R; next }

# ── 引用 ─────────────────────────────────────────────────────
/^> / { printf "%s▏%s %s\n", BAR, QUO, inline(substr($0, 3)) R; next }

# ── 待辦清單（checklist）───────────────────────────────────────
# 要在一般清單之前比對，否則 - [ ] 會先被當成普通項目。
/^[ \t]*[-*] \[[ xX]\] / {
    match($0, /^[ \t]*/)
    ind = substr($0, 1, RLENGTH)
    box = substr($0, RLENGTH + 3, 3)
    rest = substr($0, RLENGTH + 7)
    # 用 ⬜ / ✅ 而不是 ☐ / ☑。
    # 終端機的字元格大小是字型決定的，沒辦法「把符號放大」——
    # 能做的是換一個把格子填得更滿的字。☐/☑（U+2610/2611）在多數等寬字型裡
    # 畫得又小又細，⬜/✅ 是 emoji presentation，會佔滿整格。
    #
    # 顏色照樣送。字型把它們當彩色 emoji 時會忽略前景色（✅ 本來就是綠的），
    # 當文字畫時我們的橘/綠就生效 —— 兩種情況都不會出錯。
    #
    # ⚠️ 這兩個字的顯示寬度是 2，不是 1（見 iswide）。
    if (box ~ /\[[xX]\]/)
        printf "%s%s✅%s %s%s%s\n", ind, DONE, R, DIM, inline(rest), R
    else
        printf "%s%s⬜%s %s\n", ind, TODO, R, inline(rest)
    next
}

# ── 清單 ─────────────────────────────────────────────────────
/^[ \t]*[-*] / {
    match($0, /^[ \t]*/)
    ind = substr($0, 1, RLENGTH)
    rest = substr($0, RLENGTH + 3)
    printf "%s%s●%s %s\n", ind, BUL, R, inline(rest)
    next
}
/^[ \t]*[0-9]+\. / {
    match($0, /^[ \t]*/); ind = substr($0, 1, RLENGTH)
    match($0, /[0-9]+\./);  num = substr($0, RSTART, RLENGTH)
    rest = substr($0, RSTART + RLENGTH + 1)
    printf "%s%s%s%s %s\n", ind, BUL, num, R, inline(rest)
    next
}

{ print inline($0) }

END { if (nt > 0) tflush() }

function dash(n_,   o) {
    o = ""
    while (n_ > 0) { o = o "─"; n_-- }
    return o
}
function sp(n_,   o) {
    o = ""
    while (n_ > 0) { o = o " "; n_-- }
    return o
}

# ── 顯示寬度 ─────────────────────────────────────────────────
# decode / dw / iswide 與 ORD 表在 width.awk，list.awk 也要用同一份。
# 呼叫方式：awk -f width.awk -f md.awk

# ── 表格：寬度用的純文字、樣式、截斷、輸出 ────────────────────
#
# 寬度要算在「拿掉標記之後」的文字上：`code` 的反引號和 **bold** 的星號
# 都不會顯示，算進去欄寬就會多留空位。
function tplain(s) {
    gsub(/`/, "", s)
    gsub(/\*\*/, "", s)
    gsub(/~~/, "", s)
    return s
}
# 表格版的 inline()。多一個 base 參數：每次結束一段樣式後要把 base 補回去，
# 否則 reset 會把整個 cell 的樣式（例如表頭的粗體）一起關掉。
function tinline(s, base,   out, i, n, parts) {
    out = ""; n = split(s, parts, "`")
    for (i = 1; i <= n; i++) {
        if (i % 2 == 0) out = out COD_T parts[i] R base
        else            out = out emph(parts[i], base)
    }
    return out
}
# 取 s 前 wd 格，剩下的放全域 CUTREST。給「沒有斷點可用的長 token」硬切用。
function tcut(s, wd,   acc, i, wid, cw) {
    acc = ""; wid = 0; i = 1
    while (i <= length(s)) {
        decode(s, i)
        cw = iswide(CP) ? 2 : 1
        if (wid + cw > wd) break
        acc = acc substr(s, i, CLEN)
        wid += cw
        i += CLEN
    }
    CUTREST = substr(s, i)
    return acc
}
function rstrip(s) { sub(/ +$/, "", s); return s }

# 把一個 cell 折成寬度 wd 以內的若干行，結果放 WR[col, 1..n]，回傳 n。
#
# 這是「cell 內部折行」，不是讓行溢出到下一行 —— 欄寬不變、補白照補，
# 所以垂直對齊完全保留，而內容一個字都不會掉。截斷（… 省略號）是上一版的做法，
# 已經拿掉了：在唯讀的預覽裡看不到內容，比表格變長嚴重得多。
#
# 斷行規則：先切成「原子」再貪心塞。
#   - 一個寬字元自己是一個原子 —— CJK 沒有空白可斷，逐字斷正是中文的斷行規則
#   - 一串非空白的窄字元（英文詞、路徑、TFM 串）是一個原子，不從中間切
#   - 空白黏在前一個原子尾巴，所以斷在這裡時行尾不會留下看不見的空白
function twrap(s, wd, col,   i, n, ch, na, k, line, lw, t, cnt) {
    # 放得下就原樣回傳，行內樣式（`code`、**bold**）留著
    if (dw(tplain(s)) <= wd) { WR[col, 1] = s; return 1 }
    # 要折行才拿掉樣式：ANSI 碼跨行會裂開，而且會被算進寬度
    s = tplain(s)
    na = 0; i = 1; n = length(s)
    while (i <= n) {
        decode(s, i); ch = substr(s, i, CLEN)
        if (iswide(CP)) {
            na++; AT[na] = ch; AC[na] = 2; AW[na] = 2; OPEN[na] = 0
            i += CLEN; continue
        }
        if (ch == " ") {
            if (na == 0) { na++; AT[na] = ""; AC[na] = 0; AW[na] = 0 }
            AT[na] = AT[na] " "; AW[na]++       # AC 不動：尾隨空白不算進斷行判斷
            OPEN[na] = 0
            i++; continue
        }
        if (na == 0 || !OPEN[na]) { na++; AT[na] = ""; AC[na] = 0; AW[na] = 0 }
        AT[na] = AT[na] ch; AC[na]++; AW[na]++
        # 路徑分隔號與標點後面也算斷點。少了這個，
        # ~/higgs/gp/gp-agentic/kernel/common 會被硬切成 …/ke + rnel/common。
        # 斷在 / ; , . 之後至少切在有意義的地方。
        OPEN[na] = (ch == "/" || ch == ";" || ch == "," || ch == ".") ? 0 : 1
        i += CLEN
    }

    cnt = 0; line = ""; lw = 0
    for (k = 1; k <= na; k++) {
        if (line != "" && lw + AC[k] > wd) {
            cnt++; WR[col, cnt] = rstrip(line)
            line = ""; lw = 0
        }
        if (AC[k] > wd) {
            # 單一原子就比整欄寬（長路徑、netstandard2.0;net6.0;net8.0 這種）：
            # 沒有斷點可用，只能硬切。
            t = AT[k]
            while (dw(t) > wd) { cnt++; WR[col, cnt] = tcut(t, wd); t = CUTREST }
            line = t; lw = dw(t)
            continue
        }
        line = line AT[k]; lw += AW[k]
    }
    cnt++; WR[col, cnt] = rstrip(line)          # 最後一行（cell 為空時也要有一行）
    return cnt
}
function tflush(   r, c, k, big, total, out, rule, s, padn, styled, last, hmax, bg, lw) {
    total = 0
    for (c = 1; c <= tnc; c++) total += TW[c]
    total += (tnc - 1) * 3          # 每個欄縫是 " │ "

    # 塞不下就從最寬的欄一格一格砍，砍到 8 格為底。
    # 反覆砍「當下最寬的那欄」會自然把痛苦攤平，不需要另外算比例。
    #
    # 砍掉的內容不會消失 —— 超出欄寬的部分在 cell 內部折行（見 twrap）。
    # 欄數多到連 8 格都湊不出來時就讓它超出窗格；那種表格本來就不該用表格寫。
    while (total > w) {
        big = 1
        for (c = 2; c <= tnc; c++) if (TW[c] > TW[big]) big = c
        if (TW[big] <= 8) break
        TW[big]--; total--
    }

    for (r = 1; r <= tnr; r++) {
        for (c = 1; c <= tnc; c++) LN[c] = twrap(T[r, c], TW[c], c)
        hmax = 1
        for (c = 1; c <= tnc; c++) if (LN[c] > hmax) hmax = LN[c]

        # 斑馬紋（zebra striping）：隔列鋪底色。
        #
        # 這同時取代了「列間虛線」—— 相鄰兩列顏色必定不同，多行的列不會再黏成
        # 一團，不需要另外畫線去分開它們。
        #
        # 表頭不鋪（它有粗體和底下那條線），第一列資料也不鋪，
        # 這樣色塊從第二列開始，緊貼表頭底線的那列看起來乾淨。
        bg = (r > 1 && r % 2 == 1) ? ZEB : ""

        # 欄數不齊的表格（手寫時很常見）：尾端沒東西的欄就不要畫欄縫，
        # 否則會留一截「│」懸在空白上。前面缺的還是要補，對齊不能斷。
        #
        # ⚠️ last 要按「整列」算，不能每行各算一次。折行後只有第一行有內容的欄，
        # 續行如果不畫欄縫，續下來的字就會沒有邊界地飄在那裡 —— 看起來不像同一列。
        last = 0
        for (c = 1; c <= tnc; c++) if (T[r, c] != "") last = c

        for (k = 1; k <= hmax; k++) {
            out = ""; lw = 0
            for (c = 1; c <= last; c++) {
                s = (k <= LN[c] ? WR[c, k] : "")
                padn = TW[c] - dw(tplain(s))
                # base 傳 bg：cell 裡的 `code` / **bold** 結束時會送 reset，
                # 那個 reset 會把底色一起關掉，所以要立刻把 bg 補回去。
                # 表頭沒有底色，base 傳 B（粗體）—— 同樣的道理。
                styled = (r == 1 ? B tinline(s, B) R : tinline(s, bg))
                if (TA[c] == "r")      styled = sp(padn) styled
                else if (TA[c] == "c") styled = sp(int(padn / 2)) styled sp(padn - int(padn / 2))
                else                   styled = styled sp(padn)
                if (c > 1) { out = out BAR " │ " R bg; lw += 3 }
                out = out styled
                lw += TW[c]
            }
            if (bg != "") {
                # 有底色就要補滿整張表的寬度，否則色塊尾巴會缺一角
                # （欄數不齊、或這列比較短的時候）。
                #
                # ⚠️ 一定要以 reset 收尾。chooser 在每行尾巴補 \033[K，
                # 而 \033[K 是用「當前底色」清到行尾的（BCE）——
                # 底色還開著的話，斑馬紋會一路延伸到窗格右緣。
                out = bg out sp(total - lw) R
            } else {
                sub(/ +$/, "", out)   # 沒底色的話，行尾補的空白沒有作用，省下來
            }
            print out
        }
        if (r == 1) {
            rule = ""
            for (c = 1; c <= tnc; c++) rule = rule (c > 1 ? "─┼─" : "") dash(TW[c])
            printf "%s%s%s\n", BAR, rule, R
        }
    }

    # 收乾淨：同一份內容裡可能有好幾個表格，殘留的欄寬會污染下一個。
    for (c in TW) delete TW[c]
    for (c in TA) delete TA[c]
    for (c in T)  delete T[c]
    for (c in WR) delete WR[c]
    nt = 0; tnr = 0; tnc = 0
}

# ── 行內樣式 ─────────────────────────────────────────────────
function inline(s,   out, i, n, parts) {
    # `code`：奇數段落是 code
    out = ""; n = split(s, parts, "`")
    for (i = 1; i <= n; i++) {
        out = out (i % 2 == 0 ? COD " " parts[i] " " R : emph(parts[i], ""))
    }
    return out
}

# **粗體** 與 ~~刪除線~~。
#
# 不用 split() 分別處理，因為那樣一定會有一種巢狀壞掉：先切 ~~ 的話
# **~~x~~** 的星號會被拆到不同段；先切 ** 的話 ~~**x**~~ 壞掉。
# 改成從左到右掃一遍、維持兩個開關，任意巢狀與交錯都對。
#
# base：每次屬性變動都要 reset 再重新套上去，而 reset 會把呼叫端的底色
# （表格的斑馬紋）一起關掉 —— 所以 base 要跟著補回來。表格以外傳空字串。
#
# 逐位元組掃是安全的：** 與 ~~ 都是 ASCII，而 UTF-8 的續接位元組一定 ≥ 0x80，
# 不可能誤判成標記。
function emph(s, base,   out, i, n, b, k) {
    out = ""; b = 0; k = 0; i = 1; n = length(s)
    while (i <= n) {
        if (substr(s, i, 2) == "**") { b = !b; out = out emphsgr(b, k, base); i += 2; continue }
        if (substr(s, i, 2) == "~~") { k = !k; out = out emphsgr(b, k, base); i += 2; continue }
        out = out substr(s, i, 1); i++
    }
    # 標記沒有收尾（單獨一個 ** 或 ~~）就在行末關掉，不要漏到下一行
    if (b || k) out = out R base
    return out
}
function emphsgr(b, k, base) {
    return R base (b ? B : "") (k ? STRIKE : "")
}

# ── 程式碼語法高亮 ───────────────────────────────────────────
#
# 單次掃描的 tokenizer，不用 regex 的詞界。
# 原因：`\<` `\>` 是 GNU 擴充，macOS 內建的 BWK awk（20200816）不支援，
# 用 gsub 加詞界的寫法在 macOS 上會整批失效（實測過：只有字串上色、關鍵字沒有）。
function highlight(s, lang,   out, c, w, i, n, set) {
    if (lang == "sql")                  set = "sql"
    else if (lang ~ /^(cs|csharp)$/)    set = "cs"
    else return s      # 沒有 lexer 就原樣輸出：log / stack trace 本來就不該上色

    out = ""
    n = length(s)
    i = 1
    while (i <= n) {
        c = substr(s, i, 1)

        # 字串常值
        if (c == "\"" || c == "'") {
            w = c; i++
            while (i <= n) {
                w = w substr(s, i, 1)
                if (substr(s, i, 1) == c) { i++; break }
                i++
            }
            out = out STR w R
            continue
        }
        # SQL 的 -- 註解：到行尾
        if (set == "sql" && substr(s, i, 2) == "--") {
            out = out CMT substr(s, i) R
            break
        }
        # C# 的 // 註解
        if (set == "cs" && substr(s, i, 2) == "//") {
            out = out CMT substr(s, i) R
            break
        }
        # 數字
        if (c ~ /[0-9]/) {
            w = ""
            while (i <= n && substr(s, i, 1) ~ /[0-9.]/) { w = w substr(s, i, 1); i++ }
            out = out NUM w R
            continue
        }
        # 識別字：整段吃完再查表，這就是我們的詞界
        if (c ~ /[A-Za-z_]/) {
            w = ""
            while (i <= n && substr(s, i, 1) ~ /[A-Za-z0-9_]/) { w = w substr(s, i, 1); i++ }
            out = out (((set "|" toupper(w)) in KWSET) ? KW w R : w)
            continue
        }
        out = out c
        i++
    }
    return out
}
