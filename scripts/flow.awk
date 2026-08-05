# 流程圖：mermaid flowchart / graph（TD 方向）→ 文字
#
# 佈局 = Sugiyama 的前三步：斷環 → 分層（最長路徑）→ 跨層邊插虛擬節點。
# 刻意不做第四步（交叉最小化）：那要迭代重排，而在字元格裡就算排好了繞線還是會撞，
# 投資報酬率很差。一層放五個以上的節點會變吵 —— 那是這個做法的上限。
#
# 認不出來就回 ""，md.awk 照 code block 畫。
# 依賴 width.awk。全域一律 FC_ 前綴，避免跟 md.awk / seq.awk / er.awk 撞名。

function fc_put(r, col, s,   i, n, ch) {
    n = length(s); i = 1
    while (i <= n) {
        decode(s, i); ch = substr(s, i, CLEN)
        FC_G[r, col] = ch
        if (iswide(CP)) { FC_G[r, col+1] = FC_SKIP; col += 2 } else col++
        i += CLEN
    }
    if (col-1 > FC_MAXC) FC_MAXC = col-1
}
# 畫橫線／縱線時撞到對方就畫十字，不然交叉處會被吃掉一段
function fc_h(r, x,   c) {
    c = FC_G[r,x]
    if (c == "") { FC_G[r,x] = "─"; return }
    if (c == "│" || c == "┊") FC_G[r,x] = "┼"
}
function fc_v(r, x, ln,   c) {
    c = FC_G[r,x]
    if (c == "") { FC_G[r,x] = ln; return }
    if (c == "─") FC_G[r,x] = "┼"
}
function fc_row(r,   x, o) {
    o = ""
    for (x = 1; x <= FC_MAXC; x++) {
        if (FC_G[r,x] == FC_SKIP) continue
        o = o (FC_G[r,x] == "" ? " " : FC_G[r,x])
    }
    sub(/ +$/, "", o); return o
}
function fc_id(k) {
    if (!(k in FC_NI)) { FC_NN++; FC_NI[k] = FC_NN; FC_NL[FC_NN] = k; FC_NS[FC_NN] = "[" }
    return FC_NI[k]
}
function fc_bw(i) { return FC_NV[i] ? 1 : dw(FC_NL[i]) + 4 }
function fc_dfs(v,   k, e, u) {
    FC_VIS[v] = 1; FC_STK[v] = 1
    for (k = 1; k <= FC_ADJN[v]; k++) {
        e = FC_ADJ[v, k]; u = FC_ETU[e]
        if (FC_STK[u]) { FC_BACK[e] = 1; continue }
        if (!FC_VIS[u]) fc_dfs(u)
    }
    FC_STK[v] = 0
}

function flow_render(buf, n,   bi, line, prev, elab, edot, key, lab, shape, ce, arrow,
                     i, e, k, pass, ch, L, tw, x, x2, W, r, sx, tx, lo, hi, ln, g,
                     top, bot, rb, f, t, pv, ne0, b, tl, tr, bl, br, sd, out, seen) {
    FC_SKIP = sprintf("%c", 1)
    FC_NN = 0; FC_NE = 0; FC_NEU = 0; FC_NB = 0; FC_MAXC = 0; FC_MAXL = 0; FC_TOTW = 0
    for (i in FC_G)    delete FC_G[i]
    for (i in FC_NI)   delete FC_NI[i]
    for (i in FC_LC)   delete FC_LC[i]
    for (i in FC_BUS)  delete FC_BUS[i]
    for (i in FC_USED) delete FC_USED[i]
    for (i in FC_SEEN) delete FC_SEEN[i]
    for (i in FC_ADJN) delete FC_ADJN[i]
    for (i in FC_VIS)  delete FC_VIS[i]
    for (i in FC_STK)  delete FC_STK[i]
    for (i in FC_BACK) delete FC_BACK[i]
    for (i in FC_DEAD) delete FC_DEAD[i]
    for (i in FC_NV)   delete FC_NV[i]
    for (i in FC_EGM)  delete FC_EGM[i]
    seen = 0

    # ── 解析 ──
    for (bi = 1; bi <= n; bi++) {
        line = buf[bi]; gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line == "") continue
        if (line ~ /^(flowchart|graph)[ \t]/) { seen = 1; continue }
        if (line ~ /^(subgraph|end)([ \t]|$)/) continue    # subgraph 先當群組標籤忽略
        if (line ~ /^%%/) continue
        prev = 0; elab = ""; edot = 0
        # 一行可以串多段：A[x] -->|lab| B(y) --> C{z}
        while (length(line) > 0) {
            if (!match(line, /^[A-Za-z0-9_.-]+/)) break
            key = substr(line, 1, RLENGTH); line = substr(line, RLENGTH+1)
            lab = ""; shape = "["
            if      (substr(line,1,2) == "((") { shape="(("; ce=index(line,"))"); lab=substr(line,3,ce-3); line=substr(line,ce+2) }
            else if (substr(line,1,2) == "[[") { shape="[["; ce=index(line,"]]"); lab=substr(line,3,ce-3); line=substr(line,ce+2) }
            else if (substr(line,1,2) == "([") { shape="(["; ce=index(line,"])"); lab=substr(line,3,ce-3); line=substr(line,ce+2) }
            else if (substr(line,1,2) == "[(") { shape="[("; ce=index(line,")]"); lab=substr(line,3,ce-3); line=substr(line,ce+2) }
            else if (substr(line,1,1) == "[")  { shape="[";  ce=index(line,"]");  lab=substr(line,2,ce-2); line=substr(line,ce+1) }
            else if (substr(line,1,1) == "(")  { shape="(";  ce=index(line,")");  lab=substr(line,2,ce-2); line=substr(line,ce+1) }
            else if (substr(line,1,1) == "{")  { shape="{";  ce=index(line,"}");  lab=substr(line,2,ce-2); line=substr(line,ce+1) }
            gsub(/^["']|["']$/, "", lab)
            i = fc_id(key)
            if (lab != "") { FC_NL[i] = lab; FC_NS[i] = shape }
            gsub(/^[ \t]+/, "", line)
            if (prev > 0) { FC_NE++; FC_EF[FC_NE]=prev; FC_ET[FC_NE]=i; FC_EG[FC_NE]=elab; FC_ED[FC_NE]=edot; seen = 1 }
            prev = i; elab = ""; edot = 0
            if (!match(line, /^(-\.-+>?|-+>|=+>|-+)/)) break
            arrow = substr(line, 1, RLENGTH); line = substr(line, RLENGTH+1)
            edot = (arrow ~ /\./)
            gsub(/^[ \t]+/, "", line)
            if (substr(line,1,1) == "|") { ce = index(substr(line,2), "|"); elab = substr(line,2,ce-1); line = substr(line,ce+2) }
            gsub(/^[ \t]+/, "", line)
        }
    }
    if (!seen || FC_NN == 0 || FC_NE == 0) return ""

    # ── 合併平行邊（同一對節點多條）：標籤用 / 串起來 ──
    for (e = 1; e <= FC_NE; e++) {
        k = FC_EF[e] "," FC_ET[e]
        if (k in FC_SEEN) {
            if (FC_EG[e] != "") FC_EGM[k] = (FC_EGM[k]=="" ? FC_EG[e] : FC_EGM[k] " / " FC_EG[e])
            continue
        }
        FC_SEEN[k] = 1; FC_NEU++
        FC_EFU[FC_NEU]=FC_EF[e]; FC_ETU[FC_NEU]=FC_ET[e]
        FC_EGM[k]=FC_EG[e]; FC_EDU[FC_NEU]=FC_ED[e]
    }

    # ── 斷環 ──
    # ⚠️ 不能直接跑最長路徑。有環的時候（A→B→C→A）迭代會把 A 一路往下推，
    # 整張圖上下顛倒。實測過。要先 DFS 找出回邊（指向還在遞迴堆疊上的節點）。
    for (e = 1; e <= FC_NEU; e++) FC_ADJ[FC_EFU[e], ++FC_ADJN[FC_EFU[e]]] = e
    for (i = 1; i <= FC_NN; i++) if (!FC_VIS[i]) fc_dfs(i)

    # ── 分層（最長路徑，忽略回邊）──
    for (i = 1; i <= FC_NN; i++) FC_LAY[i] = 1
    for (pass = 1; pass <= FC_NN; pass++) {
        ch = 0
        for (e = 1; e <= FC_NEU; e++) {
            if (FC_BACK[e]) continue
            if (FC_LAY[FC_ETU[e]] < FC_LAY[FC_EFU[e]] + 1) { FC_LAY[FC_ETU[e]] = FC_LAY[FC_EFU[e]] + 1; ch = 1 }
        }
        if (!ch) break
    }

    # ── 跨層邊插虛擬節點（Sugiyama 第三步）──
    # 不做的話那條邊只能列成註腳。實測：C-->|足夠|P 因為 M-->P 把 P 推到第 4 層，
    # 「足夠」這條主線就從圖上消失了。
    ne0 = FC_NEU
    for (e = 1; e <= ne0; e++) {
        if (FC_BACK[e]) continue
        f = FC_EFU[e]; t = FC_ETU[e]
        if (FC_LAY[t] - FC_LAY[f] <= 1) continue
        pv = f
        for (L = FC_LAY[f] + 1; L <= FC_LAY[t] - 1; L++) {
            FC_NN++; FC_NV[FC_NN] = 1; FC_NL[FC_NN] = ""; FC_NS[FC_NN] = ""; FC_LAY[FC_NN] = L
            FC_NEU++; FC_EFU[FC_NEU] = pv; FC_ETU[FC_NEU] = FC_NN
            FC_EGM[pv "," FC_NN] = (pv == f ? FC_EGM[f "," t] : "")
            FC_EDU[FC_NEU] = FC_EDU[e]
            pv = FC_NN
        }
        FC_NEU++; FC_EFU[FC_NEU] = pv; FC_ETU[FC_NEU] = t
        FC_EGM[pv "," t] = ""; FC_EDU[FC_NEU] = FC_EDU[e]
        FC_DEAD[e] = 1
    }
    for (i = 1; i <= FC_NN; i++) {
        L = FC_LAY[i]; FC_LN[L, ++FC_LC[L]] = i
        if (L > FC_MAXL) FC_MAXL = L
    }

    # ── x 座標：層內排開，每層再整體置中 ──
    for (L = 1; L <= FC_MAXL; L++) {
        tw = -3
        for (k = 1; k <= FC_LC[L]; k++) tw += fc_bw(FC_LN[L,k]) + 3
        FC_LW[L] = tw
        if (tw > FC_TOTW) FC_TOTW = tw
    }
    for (L = 1; L <= FC_MAXL; L++) {
        x = int((FC_TOTW - FC_LW[L]) / 2) + 1
        for (k = 1; k <= FC_LC[L]; k++) {
            i = FC_LN[L,k]; FC_X[i]=x; FC_CX[i]=x+int(fc_bw(i)/2); x += fc_bw(i)+3
        }
    }

    # ── 每個層間隙要幾條匯流排：會轉彎的邊各佔一條 ──
    # 共用一條的話會變成 ┌── peek ─┘── Enter ─┐ 這種疊在一起的樣子。
    for (e = 1; e <= FC_NEU; e++) {
        if (FC_DEAD[e] || FC_BACK[e] || FC_LAY[FC_ETU[e]] != FC_LAY[FC_EFU[e]] + 1) continue
        if (FC_CX[FC_EFU[e]] != FC_CX[FC_ETU[e]]) FC_BUS[FC_LAY[FC_EFU[e]]]++
    }
    for (L = 1; L <= FC_MAXL; L++) { FC_GAPR[L] = FC_BUS[L] + 2; if (FC_GAPR[L] < 3) FC_GAPR[L] = 3 }
    FC_BASE[1] = 1
    for (L = 2; L <= FC_MAXL; L++) FC_BASE[L] = FC_BASE[L-1] + 3 + FC_GAPR[L-1]

    # ── 畫節點 ──
    for (i = 1; i <= FC_NN; i++) {
        r = FC_BASE[FC_LAY[i]]; x = FC_X[i]; W = fc_bw(i)
        if (FC_NV[i]) {
            FC_G[r,x]="│"; FC_G[r+1,x]="│"; FC_G[r+2,x]="│"
            if (x > FC_MAXC) FC_MAXC = x
            continue
        }
        tl="┌"; tr="┐"; bl="└"; br="┘"; sd="│"
        if (FC_NS[i]=="(" || FC_NS[i]=="([" || FC_NS[i]=="((") { tl="╭"; tr="╮"; bl="╰"; br="╯" }
        if (FC_NS[i]=="{") sd="◇"          # 決策節點：側邊用菱形暗示
        fc_put(r, x, tl); for (x2=x+1; x2<=x+W-2; x2++) FC_G[r,x2]="─"; fc_put(r, x+W-1, tr)
        fc_put(r+1, x, sd); fc_put(r+1, x+2, FC_NL[i]); fc_put(r+1, x+W-1, sd)
        fc_put(r+2, x, bl); for (x2=x+1; x2<=x+W-2; x2++) FC_G[r+2,x2]="─"; fc_put(r+2, x+W-1, br)
    }

    # ── 畫邊 ──
    for (e = 1; e <= FC_NEU; e++) {
        f = FC_EFU[e]; t = FC_ETU[e]; k = f "," t
        if (FC_DEAD[e]) continue
        if (FC_BACK[e] || FC_LAY[t] != FC_LAY[f] + 1) {
            FC_NB++; FC_BF[FC_NB]=f; FC_BT[FC_NB]=t; FC_BG[FC_NB]=FC_EGM[k]; FC_BD[FC_NB]=FC_BACK[e]
            continue
        }
        sx = FC_CX[f]; tx = FC_CX[t]; g = FC_LAY[f]
        top = FC_BASE[g] + 3; bot = FC_BASE[g] + 3 + FC_GAPR[g] - 1
        ln = FC_EDU[e] ? "┊" : "│"
        if (sx == tx) {
            for (r = top; r < bot; r++) fc_v(r, sx, ln)
            FC_G[bot,sx] = "▼"
            if (FC_EGM[k] != "") fc_put(top, sx+2, FC_EGM[k])
            continue
        }
        rb = top + (++FC_USED[g]) - 1
        for (r = top; r < rb; r++) fc_v(r, sx, ln)
        lo = sx<tx ? sx : tx; hi = sx>tx ? sx : tx
        FC_G[rb,sx] = (tx>sx) ? "└" : "┘"
        for (x = lo+1; x <= hi-1; x++) fc_h(rb, x)
        FC_G[rb,tx] = (tx>sx) ? "┐" : "┌"
        for (r = rb+1; r < bot; r++) fc_v(r, tx, ln)
        FC_G[bot,tx] = "▼"
        if (FC_EGM[k] != "") {
            lab = " " FC_EGM[k] " "
            fc_put(rb, lo + int((hi-lo-dw(lab))/2) + 1, lab)
        }
    }

    out = ""
    for (r = 1; r <= FC_BASE[FC_MAXL]+2; r++) out = out fc_row(r) "\n"
    # 回邊列在圖下面 —— 硬畫進格子會穿過別人的方塊
    if (FC_NB > 0) {
        out = out "\n"
        for (b = 1; b <= FC_NB; b++)
            out = out sprintf("  %s %s %s%s\n", FC_NL[FC_BF[b]],
                              (FC_BD[b] ? "⤴" : "─▶"), FC_NL[FC_BT[b]],
                              (FC_BG[b] != "" ? "   (" FC_BG[b] ")" : ""))
    }
    return out
}
