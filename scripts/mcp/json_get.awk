# 把一行 JSON 拆成 `路徑<TAB>值` 一行一筆，給 shell 用 grep 取欄位。
#
# 只做「讀得懂我們要的那幾個欄位」這件事，不是通用 JSON 函式庫：
#   .id  .method  .params.name  .params.arguments.<key>
# 陣列元素路徑是 .a.0 .a.1。物件與陣列本身不輸出，只輸出純量。
#
# 為什麼要自己寫：MCP 的 stdio transport 就是換行分隔的 JSON-RPC，
# 要零依賴就不能用 jq。產生 JSON 很簡單（跳脫規則固定），
# 難的是解析 —— 但我們需要的欄位很少，範圍是有界的。

BEGIN {
    TAB = sprintf("%c", 9)
    # 這台的 awk 是逐字元還是逐位元組？決定 \uXXXX 要怎麼還原成 UTF-8。
    # gawk 在 UTF-8 locale 下 sprintf("%c", 0x9322) 會直接給正確的字元；
    # BWK 與 busybox 是逐位元組的，得自己把 UTF-8 三個位元組編出來。
    CHARAWARE = (length("錢") == 1)
}

{
    s = $0
    n = length(s)
    i = 1
    skip_ws()
    parse("")
}

function skip_ws() {
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == " " || c == TAB || c == "\r" || c == "\n") i++
        else break
    }
}

function parse(path,   c) {
    skip_ws()
    c = substr(s, i, 1)
    if (c == "{")      parse_obj(path)
    else if (c == "[") parse_arr(path)
    else               emit(path, parse_scalar())
}

function parse_obj(path,   k) {
    i++                                  # 吃掉 {
    skip_ws()
    if (substr(s, i, 1) == "}") { i++; return }
    while (i <= n) {
        skip_ws()
        k = parse_string()
        skip_ws()
        i++                              # 吃掉 :
        parse(path "." k)
        skip_ws()
        if (substr(s, i, 1) == ",") { i++; continue }
        if (substr(s, i, 1) == "}") { i++; return }
        return                           # 格式不對就停手，不要無窮迴圈
    }
}

function parse_arr(path,   idx) {
    i++
    skip_ws()
    if (substr(s, i, 1) == "]") { i++; return }
    idx = 0
    while (i <= n) {
        parse(path "." idx)
        idx++
        skip_ws()
        if (substr(s, i, 1) == ",") { i++; continue }
        if (substr(s, i, 1) == "]") { i++; return }
        return
    }
}

function parse_string(   out, c, esc, hex) {
    i++                                  # 吃掉開頭的 "
    out = ""
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\"") { i++; return out }
        if (c == "\\") {
            i++
            esc = substr(s, i, 1)
            if      (esc == "n") out = out "\n"
            else if (esc == "t") out = out TAB
            else if (esc == "r") out = out "\r"
            else if (esc == "b") out = out sprintf("%c", 8)
            else if (esc == "f") out = out sprintf("%c", 12)
            else if (esc == "u") {
                # \uXXXX。不能只處理 ASCII —— 有些 client（例如 Python 的
                # json.dumps 預設 ensure_ascii=True）會把中文全部逃逸成 \uXXXX，
                # 不還原的話整段內容都會變成問號。
                hex = substr(s, i + 1, 4)
                i += 4
                cp = hex2(hex)
                if (cp >= 55296 && cp <= 56319 && substr(s, i + 1, 2) == "\\u") {
                    # 高位代理：跟後面的低位代理合成一個碼位（emoji 走這條）
                    lo = hex2(substr(s, i + 3, 4))
                    i += 6
                    cp = 65536 + (cp - 55296) * 1024 + (lo - 56320)
                }
                out = out utf8(cp)
            }
            else out = out esc           # \" \\ \/ 都是原字元
            i++
            continue
        }
        out = out c
        i++
    }
    return out
}

function parse_scalar(   start, c) {
    if (substr(s, i, 1) == "\"") return parse_string()
    start = i
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "," || c == "}" || c == "]" || c == " ") break
        i++
    }
    return substr(s, start, i - start)
}

function emit(path, val) {
    gsub(/\n/, "\\n", val)               # 值裡的換行要壓成一行，不然 grep 取不到
    gsub(/\r/, "\\r", val)
    print path TAB val
}

# 把碼位編成 UTF-8。
function utf8(cp) {
    if (CHARAWARE)   return sprintf("%c", cp)          # gawk 自己會編
    if (cp < 128)    return sprintf("%c", cp)
    if (cp < 2048)   return sprintf("%c%c", 192 + int(cp / 64), 128 + (cp % 64))
    if (cp < 65536)  return sprintf("%c%c%c", 224 + int(cp / 4096),
                                    128 + int(cp / 64) % 64, 128 + (cp % 64))
    return sprintf("%c%c%c%c", 240 + int(cp / 262144),
                   128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + (cp % 64))
}

function hex2(h,   d, v, j, ch) {
    d = "0123456789abcdef"
    v = 0
    for (j = 1; j <= length(h); j++) {
        ch = tolower(substr(h, j, 1))
        v = v * 16 + index(d, ch) - 1
    }
    return v
}
