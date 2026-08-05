# 時序圖 → 文字。mermaid 的 sequenceDiagram 與 PlantUML 的訊息子集共用一支。
#
# 為什麼只做時序圖：參與者是欄、訊息是列、順序就是輸入順序 ——
# 完全不需要佈局演算法。流程圖（flowchart / graph）是任意 DAG，
# 要分層、欄內排序、交叉最小化、在字元格裡繞線，那是 graphviz 等級的問題；
# 在 awk 裡寫得出來，但輸出會很醜，而一張醜的圖比原始碼更難讀。
#
# 認不出來就回空字串，呼叫端（md.awk）照原本的 code block 畫 ——
# 所以最壞情況就是看到原始碼，跟沒有這個檔一模一樣。
#
# 依賴 width.awk 的 dw() / decode() / iswide()。呼叫方式：
#     LC_ALL=C awk -f width.awk -f seq.awk -f md.awk

# ── 格子陣列 ──────────────────────────────────────────────
#
# ⚠️ 寬字元要佔兩格：第一格放字，第二格放 SQ_SKIP 標記，emit 時跳過。
# 少了這一步，畫線會插進中文字中間（實測長這樣：送─出─提─款─申─請）。
function sq_put(r, col, s,   i, n, ch) {
    n = length(s); i = 1
    while (i <= n) {
        decode(s, i); ch = substr(s, i, CLEN)
        SQ_G[r, col] = ch
        if (iswide(CP)) { SQ_G[r, col + 1] = SQ_SKIP; col += 2 } else col++
        i += CLEN
    }
    if (col - 1 > SQ_MAXC) SQ_MAXC = col - 1
}
function sq_clear(r, a, b,   x) { for (x = a; x <= b; x++) SQ_G[r, x] = " " }
function sq_hline(r, a, b, c,   x) { for (x = a; x <= b; x++) SQ_G[r, x] = c }
function sq_lifelines(r,   i) {
    for (i = 1; i <= SQ_NP; i++) if (SQ_G[r, SQ_C[i]] == "") SQ_G[r, SQ_C[i]] = "│"
}
function sq_reg(k) {
    if (!(k in SQ_PI)) { SQ_NP++; SQ_PI[k] = SQ_NP; SQ_PL[SQ_NP] = k }
    return SQ_PI[k]
}

# 一行一行吐出來，順便上色。
# 逐格比對「這格是不是線條」再決定要不要換色 —— 不做的話每一格都會前置一段
# escape，一張圖多出好幾 KB，而且 tmux 的 cell 屬性也會被塞爆。
function sq_emit(r, hdr,   x, o, ch, want, cur) {
    o = ""; cur = ""
    for (x = 1; x <= SQ_MAXC; x++) {
        ch = SQ_G[r, x]
        if (ch == SQ_SKIP) continue
        if (ch == "") ch = " "
        want = hdr ? SQ_CH : (index("│─┄▶◀┐┘", ch) > 0 ? SQ_CL : "")
        # 換色時只送新的那一段，不要先 reset 再套 —— 前景色本來就會互相取代，
        # 多送一個 reset 等於每根生命線都多四個位元組。
        if (want != cur) { o = o (want == "" ? SQ_R : want); cur = want }
        o = o ch
    }
    sub(/ +$/, "", o)
    return o (cur == "" ? "" : SQ_R)
}

# ── 進入點 ────────────────────────────────────────────────
#
# buf[1..n] 是 fence 裡的原始行。回傳畫好的字串（含換行），
# 認不出是時序圖就回 ""。
function seq_render(buf, n,   i, line, key, lab, from, to, msg, dashed, ci, rest,
                    m, a, b, need, span, add, r, f, t, lo, hi, lw, s, out, self) {
    SQ_SKIP = sprintf("%c", 1)
    SQ_R  = sprintf("%c[0m", 27)
    SQ_CL = sprintf("%c[38;5;240m", 27)   # 線條：暗灰，跟表格框線同一個色
    SQ_CH = sprintf("%c[1m", 27)          # 參與者名稱：粗體
    SQ_NP = 0; SQ_NM = 0; SQ_MAXC = 0
    for (i in SQ_G)  delete SQ_G[i]
    for (i in SQ_PI) delete SQ_PI[i]

    seen = 0
    for (i = 1; i <= n; i++) {
        line = buf[i]
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line == "") continue
        if (line ~ /^(sequenceDiagram|@startuml|@enduml)/) { seen = 1; continue }
        if (line ~ /^(title|autonumber)([ \t]|$)/) continue

        if (line ~ /^participant[ \t]+/) {
            sub(/^participant[ \t]+/, "", line)
            if (match(line, /[ \t]+as[ \t]+/)) {
                key = substr(line, 1, RSTART - 1); lab = substr(line, RSTART + RLENGTH)
            } else { key = line; lab = line }
            gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", lab)
            sq_reg(key); SQ_PL[SQ_PI[key]] = lab
            seen = 1
            continue
        }
        # A->>B: msg   A-->>B: msg   A->B   A-->B
        if (line ~ /^[^ \t]+[ \t]*-+>>?[ \t]*[^:]+:/) {
            dashed = (line ~ /--+>/)
            match(line, /-+>>?/)
            from = substr(line, 1, RSTART - 1); rest = substr(line, RSTART + RLENGTH)
            ci = index(rest, ":")
            to = substr(rest, 1, ci - 1); msg = substr(rest, ci + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", from); gsub(/^[ \t]+|[ \t]+$/, "", to)
            gsub(/^[ \t]+|[ \t]+$/, "", msg)
            SQ_NM++
            SQ_MF[SQ_NM] = sq_reg(from); SQ_MT[SQ_NM] = sq_reg(to)
            SQ_MG[SQ_NM] = msg; SQ_MD[SQ_NM] = dashed
            seen = 1
            continue
        }
        # 有不認得的行就整張放棄 —— 半張圖比原始碼難讀。
        return ""
    }
    if (!seen || SQ_NP == 0 || SQ_NM == 0) return ""

    # ── 排版 ──
    for (i = 1; i <= SQ_NP; i++) SQ_W[i] = dw(SQ_PL[i])
    # 相鄰兩欄至少要放得下兩邊標籤的一半
    for (i = 1; i < SQ_NP; i++) SQ_SEP[i] = int(SQ_W[i] / 2) + int(SQ_W[i+1] / 2) + 4
    # 再撐開到跨過去的最長訊息放得下
    for (m = 1; m <= SQ_NM; m++) {
        a = SQ_MF[m] < SQ_MT[m] ? SQ_MF[m] : SQ_MT[m]
        b = SQ_MF[m] > SQ_MT[m] ? SQ_MF[m] : SQ_MT[m]
        if (a == b) continue
        need = dw(SQ_MG[m]) + 4
        span = 0; for (i = a; i < b; i++) span += SQ_SEP[i]
        if (need > span) {
            add = int((need - span) / (b - a)) + 1
            for (i = a; i < b; i++) SQ_SEP[i] += add
        }
    }
    SQ_C[1] = int(SQ_W[1] / 2) + 1
    for (i = 2; i <= SQ_NP; i++) SQ_C[i] = SQ_C[i-1] + SQ_SEP[i-1]

    # ── 畫 ──
    r = 1
    for (i = 1; i <= SQ_NP; i++) sq_put(r, SQ_C[i] - int(SQ_W[i] / 2), SQ_PL[i])
    r++; sq_lifelines(r)
    for (m = 1; m <= SQ_NM; m++) {
        f = SQ_C[SQ_MF[m]]; t = SQ_C[SQ_MT[m]]
        self = (SQ_MF[m] == SQ_MT[m])
        if (self) {
            # 自己送給自己：畫一個往右折的小迴圈。
            # 沒有這條的話箭頭會退化成一個孤零零的 ◀，看起來像壞掉。
            r++; sq_lifelines(r)
            SQ_G[r, f] = "│"; SQ_G[r, f + 1] = "─"; SQ_G[r, f + 2] = "┐"
            sq_put(r, f + 4, SQ_MG[m])
            r++; sq_lifelines(r)
            SQ_G[r, f] = "◀"; SQ_G[r, f + 1] = "─"; SQ_G[r, f + 2] = "┘"
            r++; sq_lifelines(r)
            continue
        }
        lo = f < t ? f : t; hi = f > t ? f : t
        # 標籤自己一行，置中在跨距上 —— 比跨距長也不會破壞箭頭那行
        r++; sq_lifelines(r)
        lw = dw(SQ_MG[m])
        s = lo + int((hi - lo - lw) / 2); if (s < 1) s = 1
        sq_clear(r, s, s + lw - 1); sq_put(r, s, SQ_MG[m])
        r++
        sq_hline(r, lo, hi, SQ_MD[m] ? "┄" : "─")
        SQ_G[r, f] = "│"
        SQ_G[r, t] = (t > f) ? "▶" : "◀"
        for (i = 1; i <= SQ_NP; i++) if (SQ_C[i] < lo || SQ_C[i] > hi) SQ_G[r, SQ_C[i]] = "│"
        r++; sq_lifelines(r)
    }

    out = ""
    for (i = 1; i <= r; i++) out = out sq_emit(i, i == 1) "\n"
    return out
}
