# C4：mermaid C4Context / C4Container / C4Component → 文字
#
# ⚠️ 這裡跟 mermaid 的做法不一樣，而且是刻意的。
#
# mermaid 的 c4Renderer 完全不做圖佈局：c4ShapeInRow = 4、c4BoundaryInRow = 2，
# 固定格子換行、保留巢狀，然後把關係線畫在那個版面「上面」。
# 它敢那樣做是因為 SVG 的線可以任意交叉重疊；字元格沒有那個本錢 ——
# 兩條線交叉在同一格就只能二選一。
#
# 所以這裡選另一邊：**把巢狀攤平成圖，換到線**。
# 邊界不畫成框，改成節點內文的一行 ⟨GP 後台⟩ —— 資訊還在，但可以連線了。
# 第一版是反過來的（畫巢狀框、關係列成清單），實際用起來就是「一堆方塊加一份
# 清單」，而 mermaid 原始碼本來就是一份清單。
#
# 認不出來就回 ""。依賴 width.awk 與 graph.awk。

function c4_render(buf, n,   bi, line, kind, args, na, A, i, j, k, sp, out,
                   seen, ne, f, t, tag, nb) {
    gr_reset()
    seen = 0; ne = 0; sp = 0
    for (i in C4_AL) delete C4_AL[i]
    for (i in C4_TY) delete C4_TY[i]
    for (i in C4_DS) delete C4_DS[i]
    for (i in C4_BD) delete C4_BD[i]
    C4_STK[0] = ""

    for (bi = 1; bi <= n; bi++) {
        line = buf[bi]; gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line == "") continue
        if (line ~ /^C4(Context|Container|Component|Dynamic|Deployment)/) { seen = 1; continue }
        if (line ~ /^(title|UpdateLayoutConfig|UpdateElementStyle|UpdateRelStyle)/) continue
        if (line ~ /^%%/) continue
        if (line == "}") { if (sp > 0) sp--; continue }

        if (!match(line, /^[A-Za-z_][A-Za-z_0-9]*[ \t]*\(/)) return ""
        kind = substr(line, 1, RSTART + RLENGTH - 2); gsub(/[ \t]*\($/, "", kind)
        args = substr(line, RSTART + RLENGTH)
        sub(/\)[ \t]*\{?[ \t]*$/, "", args)
        na = split(args, A, /[ \t]*,[ \t]*/)
        for (k = 1; k <= na; k++) gsub(/^"|"$/, "", A[k])
        if (na < 1 || A[1] == "") return ""

        if (kind ~ /Rel/) {
            ne++
            C4_RA[ne] = A[1]; C4_RB[ne] = A[2]; C4_RL[ne] = (na >= 3 ? A[3] : "")
            C4_RT[ne] = (na >= 4 ? A[4] : ""); C4_RBI[ne] = (kind ~ /^BiRel/)
            seen = 1; continue
        }
        if (kind ~ /Boundary$/) {
            # 邊界不建節點 —— 只記名字，之後掛在子節點的內文上
            sp++; C4_STK[sp] = (na >= 2 ? A[2] : A[1])
            seen = 1; continue
        }
        i = gr_node(A[1])
        C4_AL[A[1]] = i
        GR_T[i] = (na >= 2 ? A[2] : A[1])
        # Container / Component 的第 3 個參數是技術，第 4 個才是說明
        if (kind ~ /^(Container|Component)/ && na >= 4) { C4_TY[i] = kind ": " A[3]; C4_DS[i] = A[4] }
        else { C4_TY[i] = kind; C4_DS[i] = (na >= 3 ? A[3] : "") }
        C4_BD[i] = C4_STK[sp]
        seen = 1
    }
    if (!seen || GR_NN == 0) return ""

    # 節點內文：[型別] / 說明 / ⟨所屬邊界⟩
    for (i = 1; i <= GR_NN; i++) {
        nb = 0
        if (C4_TY[i] != "") GR_B[i, ++nb] = "[" C4_TY[i] "]"
        if (C4_DS[i] != "") GR_B[i, ++nb] = C4_DS[i]
        if (C4_BD[i] != "") GR_B[i, ++nb] = "⟨" C4_BD[i] "⟩"
        GR_BN[i] = nb
        # Person 用圓角，一眼分得出「人」和「系統」
        if (C4_TY[i] ~ /^Person/) GR_SH[i] = "("
    }
    for (k = 1; k <= ne; k++) {
        if (!(C4_RA[k] in C4_AL) || !(C4_RB[k] in C4_AL)) continue
        f = C4_AL[C4_RA[k]]; t = C4_AL[C4_RB[k]]
        gr_edge(f, t, C4_RL[k] (C4_RT[k] != "" ? " [" C4_RT[k] "]" : ""), 0)
        # 雙向就再補一條反向的，分層時它會變成回邊、列在註腳
        if (C4_RBI[k]) gr_edge(t, f, "", 0)
    }
    if (GR_NE == 0) return ""
    return gr_render()
}
