# ER 圖：mermaid erDiagram → 文字
#
# 不做圖佈局。ER 要回答的是「有哪些實體、各有什麼欄位、彼此什麼關係」——
# 實體畫成帶欄位的方塊，關係列成一張對齊的表。這比硬畫連線清楚，也不用繞線。
#
# 認不出來就回 ""。依賴 width.awk。全域一律 ER_ 前綴。

function er_pad(s, n,   o) { o = s; n -= dw(s); while (n-- > 0) o = o " "; return o }
function er_dn(n,   o) { o = ""; while (n-- > 0) o = o "─"; return o }

# ||--o{ / }o--|| / ||--|| / }|..|{ …→ 左右兩端的基數
# 左端看前兩個字元，右端看後兩個。..（虛線）在 mermaid 裡表示非識別關係，
# 對「看得懂」沒有差別，所以不區分。
function er_card(s,   l, r) {
    if      (substr(s,1,2) == "||") l = "1"
    else if (substr(s,1,2) == "}o") l = "0..n"
    else if (substr(s,1,2) == "}|") l = "1..n"
    else if (substr(s,1,2) == "o|") l = "0..1"
    else l = "?"
    if      (substr(s,length(s)-1) == "||") r = "1"
    else if (substr(s,length(s)-1) == "o{") r = "0..n"
    else if (substr(s,length(s)-1) == "|{") r = "1..n"
    else if (substr(s,length(s)-1) == "|o") r = "0..1"
    else r = "?"
    return l "\t" r
}

function er_render(buf, n,   bi, line, cur, inb, a, b, lab, rel, rest, ci,
                   i, j, k, w, w1, w2, w3, c, out, seen, nm) {
    ER_R   = sprintf("%c[0m", 27)
    ER_B   = sprintf("%c[1m", 27)
    ER_BAR = sprintf("%c[38;5;240m", 27)
    ER_NE = 0; ER_NR = 0; seen = 0; inb = 0
    for (i in ER_EI) delete ER_EI[i]
    for (i in ER_AN) delete ER_AN[i]
    for (i in ER_AT) delete ER_AT[i]

    for (bi = 1; bi <= n; bi++) {
        line = buf[bi]; gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line == "") continue
        if (line ~ /^erDiagram/) { seen = 1; continue }
        if (line ~ /^%%/) continue
        if (inb) {
            if (line == "}") { inb = 0; continue }
            ER_AT[cur, ++ER_AN[cur]] = line
            continue
        }
        # ENTITY {  —— 欄位區塊的開頭
        if (line ~ /\{$/ && line !~ /--/ && line !~ /\.\./) {
            cur = line; sub(/[ \t]*\{$/, "", cur)
            if (!(cur in ER_EI)) { ER_EI[cur] = ++ER_NE; ER_EL[ER_NE] = cur }
            inb = 1; seen = 1; continue
        }
        # A ||--o{ B : label
        if (match(line, /[|}o][|}o{.\-]+[|}o{]/)) {
            rel = substr(line, RSTART, RLENGTH)
            a = substr(line, 1, RSTART-1); rest = substr(line, RSTART+RLENGTH)
            gsub(/^[ \t]+|[ \t]+$/, "", a)
            ci = index(rest, ":")
            if (ci > 0) { b = substr(rest, 1, ci-1); lab = substr(rest, ci+1) }
            else        { b = rest; lab = "" }
            gsub(/^[ \t]+|[ \t]+$/, "", b)
            gsub(/^[ \t]+|[ \t]+$/, "", lab); gsub(/^"|"$/, "", lab)
            if (a == "" || b == "") return ""
            if (!(a in ER_EI)) { ER_EI[a] = ++ER_NE; ER_EL[ER_NE] = a }
            if (!(b in ER_EI)) { ER_EI[b] = ++ER_NE; ER_EL[ER_NE] = b }
            ER_NR++; ER_RA[ER_NR]=a; ER_RB[ER_NR]=b; ER_RR[ER_NR]=rel; ER_RL[ER_NR]=lab
            seen = 1; continue
        }
        return ""       # 有不認得的行就整張放棄
    }
    if (!seen || ER_NE == 0) return ""

    out = ""
    for (i = 1; i <= ER_NE; i++) {
        nm = ER_EL[i]
        w = dw(nm)
        for (j = 1; j <= ER_AN[nm]; j++) if (dw(ER_AT[nm,j]) > w) w = dw(ER_AT[nm,j])
        out = out ER_BAR "┌─" er_dn(w) "─┐" ER_R "\n"
        out = out ER_BAR "│" ER_R " " ER_B er_pad(nm, w) ER_R " " ER_BAR "│" ER_R "\n"
        # 沒有欄位就不要畫分隔線 —— 空方塊裡多一條橫線看起來像壞掉
        if (ER_AN[nm] > 0) {
            out = out ER_BAR "├─" er_dn(w) "─┤" ER_R "\n"
            for (j = 1; j <= ER_AN[nm]; j++)
                out = out ER_BAR "│" ER_R " " er_pad(ER_AT[nm,j], w) " " ER_BAR "│" ER_R "\n"
        }
        out = out ER_BAR "└─" er_dn(w) "─┘" ER_R "\n"
        if (i < ER_NE) out = out "\n"
    }

    if (ER_NR > 0) {
        w1 = 0; w2 = 0; w3 = 0
        for (k = 1; k <= ER_NR; k++) {
            split(er_card(ER_RR[k]), c, "\t")
            ER_LC[k] = c[1]; ER_RC[k] = c[2]
            if (dw(ER_RA[k]) > w1) w1 = dw(ER_RA[k])
            if (dw(ER_LC[k]) > w2) w2 = dw(ER_LC[k])
            if (dw(ER_RC[k]) > w3) w3 = dw(ER_RC[k])
        }
        out = out "\n" ER_B "關係" ER_R "\n"
        for (k = 1; k <= ER_NR; k++)
            out = out sprintf("  %s %s%s ──%s %s%s%s %s%s\n",
                        er_pad(ER_RA[k], w1),
                        ER_BAR, er_pad(ER_LC[k], w2), ER_R,
                        ER_BAR, er_pad(ER_RC[k], w3), ER_R,
                        ER_RB[k], (ER_RL[k] != "" ? "   " ER_RL[k] : ""))
    }
    return out
}
