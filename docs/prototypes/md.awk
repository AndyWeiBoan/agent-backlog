# 極簡 markdown → ANSI renderer（POSIX awk，零外部依賴）
# 原型：證明純 tmux plugin 也能自己做 render 與語法高亮。
#
# 刻意不做「換行」與「表格對齊」—— 那兩件事需要 East Asian Width 計算，
# awk 拿不到 codepoint。但內容是印進 pane 的，終端機自己會按顯示寬度折行，
# 所以不需要我們算。程式碼區塊用左側 │ 邊框而不是滿版底色，也就不必補寬度。

BEGIN {
    E   = sprintf("%c[", 27)
    R   = E "0m"          # reset
    B   = E "1m"          # bold
    DIM = E "2m"
    # 256 色
    H1  = E "1;38;5;39m"  # 標題一：亮藍
    H2  = E "1;38;5;42m"  # 標題二：綠
    H3  = E "1;38;5;214m" # 標題三：橘
    BUL = E "38;5;214m"   # bullet 符號
    COD = E "38;5;231;48;5;236m"  # inline code：淺字深底
    BAR = E "38;5;240m"   # 邊框
    QUO = E "38;5;108m"   # 引用

    # 語法高亮用的色
    KW  = E "38;5;81m"    # 關鍵字
    STR = E "38;5;186m"   # 字串
    NUM = E "38;5;141m"   # 數字
    CMT = E "38;5;244m"   # 註解

    # 關鍵字表：查表用大寫，所以 SQL 的大小寫寫法都吃得到
    sqlkw = "SELECT FROM WHERE AND OR NOT NULL INNER LEFT RIGHT OUTER JOIN ON GROUP ORDER BY HAVING AS SUM COUNT COALESCE DISTINCT INSERT INTO VALUES UPDATE SET DELETE CREATE INDEX TABLE LIMIT OFFSET CASE WHEN THEN ELSE END WITH UNION ALL IS IN EXISTS"
    cskw  = "PUBLIC PRIVATE PROTECTED INTERNAL SEALED CLASS INTERFACE RECORD STRUCT VAR AWAIT ASYNC RETURN NEW IF ELSE FOREACH FOR WHILE THROW TRY CATCH FINALLY USING NAMESPACE STATIC READONLY CONST TRUE FALSE NULL THIS BASE VOID TASK"
    n = split(sqlkw, a, " "); for (i = 1; i <= n; i++) { KWSET["sql|" a[i]] = 1 }
    n = split(cskw,  a, " "); for (i = 1; i <= n; i++) { KWSET["cs|"  a[i]] = 1 }
    fence = 0
}

# ── 程式碼區塊 ───────────────────────────────────────────────
/^```/ {
    if (fence == 0) {
        fence = 1
        lang = substr($0, 4)
        gsub(/[ \t]+$/, "", lang)
        printf "%s┌─%s%s%s\n", BAR, (lang == "" ? "" : " " B lang R BAR " "), "─────", R
    } else {
        fence = 0
        printf "%s└──────%s\n", BAR, R
    }
    next
}
fence == 1 {
    printf "%s│%s %s\n", BAR, R, highlight($0, lang)
    next
}

# ── 標題 ─────────────────────────────────────────────────────
/^### / { printf "%s▸ %s%s\n", H3, substr($0, 5), R; next }
/^## /  { printf "\n%s┃ %s%s\n", H2, substr($0, 4), R; next }
/^# /   { printf "\n%s█ %s%s\n", H1, substr($0, 3), R; next }

# ── 水平線 ───────────────────────────────────────────────────
/^---+$/ { printf "%s────────────────────────────────%s\n", BAR, R; next }

# ── 引用 ─────────────────────────────────────────────────────
/^> / { printf "%s▏%s %s\n", BAR, QUO, inline(substr($0, 3)) R; next }

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

# ── 行內樣式 ─────────────────────────────────────────────────
function inline(s,   out, i, n, parts) {
    # `code`：奇數段落是 code
    out = ""; n = split(s, parts, "`")
    for (i = 1; i <= n; i++) {
        out = out (i % 2 == 0 ? COD " " parts[i] " " R : bolds(parts[i]))
    }
    return out
}
function bolds(s,   out, i, n, parts) {
    out = ""; n = split(s, parts, "\\*\\*")
    for (i = 1; i <= n; i++) {
        out = out (i % 2 == 0 ? B parts[i] R : parts[i])
    }
    return out
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
