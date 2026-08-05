# ER 圖：mermaid erDiagram → 文字
#
# 第一版只畫方塊、關係列成清單 —— 但 mermaid 原始碼本來就是一份清單，
# 那等於沒加價值。改成走 graph.awk 的分層引擎，真的把線畫出來。
#
# 邊的方向抄 mermaid 的做法（erRenderer.js 的註解寫得很清楚）：
# ER 圖本質上是無向的，但 one-to-many 時把「一」的那邊當 parent 放上面比較直覺，
# 因為 ER 圖裡絕大多數關係都是 one-to-many。
#
# 認不出來就回 ""。依賴 width.awk 與 graph.awk。

# ||--o{ / }o--|| / ||--|| / }|..|{ …→ 左右兩端的基數。
# ..（虛線）在 mermaid 裡是非識別關係，對「看得懂」沒差，所以不區分。
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
function er_many(c) { return (c == "0..n" || c == "1..n") }

function er_render(buf, n,   bi, line, cur, inb, a, b, lab, rel, rest, ci, c,
                   i, j, k, ai, bi2, lc, rc, seen, ne) {
    gr_reset()
    seen = 0; inb = 0; ne = 0
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
            gr_node(cur)
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
            ai = gr_node(a); bi2 = gr_node(b)
            split(er_card(rel), c, "\t")
            lc = c[1]; rc = c[2]
            ne++
            # 「一」的那邊在上。左邊是多、右邊是一 → 反向連，讓 parent 在上面。
            # 基數放線的兩端，關係名稱才當標籤 —— 全部擠成一個標籤的話
            # 兩條邊的字會互相蓋掉（實測 "1 ── 0..n  提出" 就會）。
            if (er_many(lc) && !er_many(rc))
                gr_edge_c(bi2, ai, lab, 0, rc, lc)
            else
                gr_edge_c(ai, bi2, lab, 0, lc, rc)
            seen = 1; continue
        }
        return ""       # 有不認得的行就整張放棄
    }
    if (!seen || GR_NN == 0) return ""

    # 欄位塞進節點內文
    for (i = 1; i <= GR_NN; i++) {
        cur = GR_T[i]
        GR_BN[i] = ER_AN[cur] + 0
        for (j = 1; j <= ER_AN[cur]; j++) GR_B[i, j] = ER_AT[cur, j]
    }
    # 完全沒有關係的話就沒有線可畫，退回讓 md.awk 印原始碼比較誠實
    if (ne == 0) return ""
    return gr_render()
}
