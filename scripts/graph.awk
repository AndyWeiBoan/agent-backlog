# 分層圖引擎：節點（可變高度）+ 邊 → 文字。flowchart / erDiagram / C4 共用。
#
# 為什麼要抽出來：ER 與 C4 第一版只畫方塊、關係列成清單 ——
# 但 mermaid 原始碼本來就是一份清單，那等於沒加價值。線才是重點，
# 而畫線就是圖佈局，那個東西 flowchart 已經有了。差別只在
# flowchart 的方塊固定三行高，ER 要塞欄位、C4 要塞型別與說明。
#
# 佈局 = Sugiyama 的前三步：斷環 → 分層（最長路徑）→ 跨層邊插虛擬節點。
# 刻意不做第四步（交叉最小化）：要迭代重排，而在字元格裡就算排好了繞線還是會撞，
# 投資報酬率很差。一層五個以上節點會變吵 —— 那是這個做法的上限。
#
# 呼叫端要先填好這些全域，再叫 gr_render()：
#   GR_NN                節點數
#   GR_T[i]              標題（第一行，粗體）
#   GR_BN[i], GR_B[i,k]  內文行數與內容（0 = 只有標題）
#   GR_SH[i]             形狀："[" 方角（預設）、"(" 圓角、"{" 決策
#   GR_NE                邊數
#   GR_F[e], GR_TO[e]    起點 / 終點節點編號
#   GR_L[e]              邊的標籤（畫在線的中間）
#   GR_D[e]              1 = 虛線
#   GR_CF[e], GR_CT[e]   線兩端的小標記（ER 的基數用；空字串 = 不畫）
# 依賴 width.awk。

function gr_put(r, col, s,   i, n, ch) {
    n = length(s); i = 1
    while (i <= n) {
        decode(s, i); ch = substr(s, i, CLEN)
        GR_G[r, col] = ch
        if (iswide(CP)) { GR_G[r, col+1] = GR_SKIP; col += 2 } else col++
        i += CLEN
    }
    if (col-1 > GR_MAXC) GR_MAXC = col-1
}
# 畫橫線／縱線時撞到對方就畫十字，不然交叉處會被吃掉一段
function gr_h(r, x,   c) {
    c = GR_G[r,x]
    if (c == "") { GR_G[r,x] = "─"; return }
    if (c == "│" || c == "┊") GR_G[r,x] = "┼"
}
function gr_v(r, x, ln,   c) {
    c = GR_G[r,x]
    if (c == "") { GR_G[r,x] = ln; return }
    if (c == "─") GR_G[r,x] = "┼"
}
# 上色：逐格判斷「這格是不是線條」。換色時只送新的那一段，不要先 reset 再套 ——
# 不然每一格都前置一段 escape，一張圖多好幾 KB。
function gr_row(r,   x, o, ch, want, cur) {
    o = ""; cur = ""
    for (x = 1; x <= GR_MAXC; x++) {
        ch = GR_G[r,x]
        if (ch == GR_SKIP) continue
        if (ch == "") ch = " "
        want = (index("│─┄┊▼◀▶┌┐└┘├┤┼╭╮╰╯◇", ch) > 0) ? GR_CL : ""
        if (want != cur) { o = o (want == "" ? GR_R : want); cur = want }
        o = o ch
    }
    sub(/ +$/, "", o)
    return o (cur == "" ? "" : GR_R)
}
function gr_w(i,   w, k) {
    if (GR_V[i]) return 1
    w = dw(GR_T[i])
    for (k = 1; k <= GR_BN[i]; k++) if (dw(GR_B[i,k]) > w) w = dw(GR_B[i,k])
    return w + 4
}
function gr_h_of(i) {
    if (GR_V[i]) return 1
    return 3 + (GR_BN[i] > 0 ? GR_BN[i] + 1 : 0)   # 上框 + 標題 + 下框 (+ 分隔線 + 內文)
}
function gr_dfs(v,   k, e, u) {
    GR_VIS[v] = 1; GR_STK[v] = 1
    for (k = 1; k <= GR_ADJN[v]; k++) {
        e = GR_ADJ[v, k]; u = GR_ETU[e]
        if (GR_STK[u]) { GR_BACK[e] = 1; continue }
        if (!GR_VIS[u]) gr_dfs(u)
    }
    GR_STK[v] = 0
}

function gr_render(   i, e, k, pass, ch, L, tw, x, x2, W, H, r, sx, tx, lo, hi, ln,
                   g, top, bot, rb, f, t, pv, ne0, b, tl, tr, bl, br, sd, out, key) {
    GR_SKIP = sprintf("%c", 1)
    GR_R  = sprintf("%c[0m", 27)
    GR_CL = sprintf("%c[38;5;240m", 27)
    GR_B_ = sprintf("%c[1m", 27)
    GR_NEU = 0; GR_NB = 0; GR_MAXC = 0; GR_MAXL = 0; GR_TOTW = 0
    for (i in GR_G)    delete GR_G[i]
    for (i in GR_LC)   delete GR_LC[i]
    for (i in GR_BUS)  delete GR_BUS[i]
    for (i in GR_USED) delete GR_USED[i]
    for (i in GR_SEEN) delete GR_SEEN[i]
    for (i in GR_ADJN) delete GR_ADJN[i]
    for (i in GR_VIS)  delete GR_VIS[i]
    for (i in GR_STK)  delete GR_STK[i]
    for (i in GR_BACK) delete GR_BACK[i]
    for (i in GR_DEAD) delete GR_DEAD[i]
    for (i in GR_V)    delete GR_V[i]
    for (i in GR_EGM)  delete GR_EGM[i]
    for (i in GR_CFM)  delete GR_CFM[i]
    for (i in GR_CTM)  delete GR_CTM[i]
    for (i in GR_MAXH) delete GR_MAXH[i]

    # 合併平行邊：標籤用 / 串起來
    for (e = 1; e <= GR_NE; e++) {
        key = GR_F[e] "," GR_TO[e]
        if (key in GR_SEEN) {
            if (GR_L[e] != "") GR_EGM[key] = (GR_EGM[key]=="" ? GR_L[e] : GR_EGM[key] " / " GR_L[e])
            continue
        }
        GR_SEEN[key] = 1; GR_NEU++
        GR_EFU[GR_NEU] = GR_F[e]; GR_ETU[GR_NEU] = GR_TO[e]
        GR_EGM[key] = GR_L[e]; GR_EDU[GR_NEU] = GR_D[e]
        GR_CFM[key] = GR_CF[e]; GR_CTM[key] = GR_CT[e]
    }
    # 斷環。⚠️ 不能直接跑最長路徑 —— 有環時迭代會把起點一路往下推，整張圖上下顛倒。
    for (e = 1; e <= GR_NEU; e++) GR_ADJ[GR_EFU[e], ++GR_ADJN[GR_EFU[e]]] = e
    for (i = 1; i <= GR_NN; i++) if (!GR_VIS[i]) gr_dfs(i)
    # 分層
    for (i = 1; i <= GR_NN; i++) GR_LAY[i] = 1
    for (pass = 1; pass <= GR_NN; pass++) {
        ch = 0
        for (e = 1; e <= GR_NEU; e++) {
            if (GR_BACK[e]) continue
            if (GR_LAY[GR_ETU[e]] < GR_LAY[GR_EFU[e]] + 1) { GR_LAY[GR_ETU[e]] = GR_LAY[GR_EFU[e]] + 1; ch = 1 }
        }
        if (!ch) break
    }
    # 跨層邊插虛擬節點。不做的話那條邊只能列註腳，主線會從圖上消失。
    ne0 = GR_NEU
    for (e = 1; e <= ne0; e++) {
        if (GR_BACK[e]) continue
        f = GR_EFU[e]; t = GR_ETU[e]
        if (GR_LAY[t] - GR_LAY[f] <= 1) continue
        pv = f
        for (L = GR_LAY[f] + 1; L <= GR_LAY[t] - 1; L++) {
            GR_NN++; GR_V[GR_NN] = 1; GR_T[GR_NN] = ""; GR_BN[GR_NN] = 0; GR_LAY[GR_NN] = L
            GR_NEU++; GR_EFU[GR_NEU] = pv; GR_ETU[GR_NEU] = GR_NN
            GR_EGM[pv "," GR_NN] = (pv == f ? GR_EGM[f "," t] : "")
            GR_CFM[pv "," GR_NN] = (pv == f ? GR_CFM[f "," t] : "")
            GR_EDU[GR_NEU] = GR_EDU[e]
            pv = GR_NN
        }
        GR_NEU++; GR_EFU[GR_NEU] = pv; GR_ETU[GR_NEU] = t
        GR_EGM[pv "," t] = ""; GR_CTM[pv "," t] = GR_CTM[f "," t]
        GR_EDU[GR_NEU] = GR_EDU[e]
        GR_DEAD[e] = 1
    }
    for (i = 1; i <= GR_NN; i++) {
        L = GR_LAY[i]; GR_LN[L, ++GR_LC[L]] = i
        if (L > GR_MAXL) GR_MAXL = L
        H = gr_h_of(i); if (H > GR_MAXH[L]) GR_MAXH[L] = H
    }
    # x 座標：層內排開，每層再整體置中
    for (L = 1; L <= GR_MAXL; L++) {
        tw = -3
        for (k = 1; k <= GR_LC[L]; k++) tw += gr_w(GR_LN[L,k]) + 3
        GR_LW[L] = tw
        if (tw > GR_TOTW) GR_TOTW = tw
    }
    for (L = 1; L <= GR_MAXL; L++) {
        x = int((GR_TOTW - GR_LW[L]) / 2) + 1
        for (k = 1; k <= GR_LC[L]; k++) {
            i = GR_LN[L,k]; GR_X[i]=x; GR_CX[i]=x+int(gr_w(i)/2); x += gr_w(i)+3
        }
    }
    # 每個層間隙要幾條匯流排：會轉彎的邊各佔一條（共用會疊在一起）
    for (e = 1; e <= GR_NEU; e++) {
        if (GR_DEAD[e] || GR_BACK[e] || GR_LAY[GR_ETU[e]] != GR_LAY[GR_EFU[e]] + 1) continue
        if (GR_CX[GR_EFU[e]] != GR_CX[GR_ETU[e]]) GR_BUS[GR_LAY[GR_EFU[e]]]++
    }
    # 間隙的列數：第一列只放兩端的基數標記，接著每條轉彎的邊各一條匯流排，
    # 最後一列放箭頭。基數跟標籤共用一列的話會互相蓋掉（實測 "┌ 提出1"）。
    for (L = 1; L <= GR_MAXL; L++) { GR_GAPR[L] = GR_BUS[L] + 3; if (GR_GAPR[L] < 3) GR_GAPR[L] = 3 }
    GR_BASE[1] = 1
    for (L = 2; L <= GR_MAXL; L++) GR_BASE[L] = GR_BASE[L-1] + GR_MAXH[L-1] + GR_GAPR[L-1]

    # 畫節點
    for (i = 1; i <= GR_NN; i++) {
        r = GR_BASE[GR_LAY[i]]; x = GR_X[i]; W = gr_w(i)
        if (GR_V[i]) {
            for (k = 0; k < GR_MAXH[GR_LAY[i]]; k++) GR_G[r+k, x] = "│"
            if (x > GR_MAXC) GR_MAXC = x
            continue
        }
        tl="┌"; tr="┐"; bl="└"; br="┘"; sd="│"
        if (GR_SH[i]=="(") { tl="╭"; tr="╮"; bl="╰"; br="╯" }
        if (GR_SH[i]=="{") sd="◇"
        gr_put(r, x, tl); for (x2=x+1; x2<=x+W-2; x2++) GR_G[r,x2]="─"; gr_put(r, x+W-1, tr)
        # ⚠️ 絕對不要把 ANSI 逃逸碼塞進格子。gr_put 是一格一個字元，
        # escape 的每個位元組都會佔掉一格，整張圖會爛掉。
        # 上色統一在 gr_row 出場時按「這格是不是線條」判斷。
        gr_put(r+1, x, sd); gr_put(r+1, x+2, GR_T[i]); gr_put(r+1, x+W-1, sd)
        r2 = r + 2
        if (GR_BN[i] > 0) {
            gr_put(r2, x, "├"); for (x2=x+1; x2<=x+W-2; x2++) GR_G[r2,x2]="─"; gr_put(r2, x+W-1, "┤")
            for (k = 1; k <= GR_BN[i]; k++) {
                gr_put(r2+k, x, sd); gr_put(r2+k, x+2, GR_B[i,k]); gr_put(r2+k, x+W-1, sd)
            }
            r2 = r2 + GR_BN[i] + 1
        }
        gr_put(r2, x, bl); for (x2=x+1; x2<=x+W-2; x2++) GR_G[r2,x2]="─"; gr_put(r2, x+W-1, br)
    }
    # 畫邊
    for (e = 1; e <= GR_NEU; e++) {
        f = GR_EFU[e]; t = GR_ETU[e]; key = f "," t
        if (GR_DEAD[e]) continue
        if (GR_BACK[e] || GR_LAY[t] != GR_LAY[f] + 1) {
            GR_NB++; GR_BF[GR_NB]=f; GR_BT[GR_NB]=t
            GR_BG[GR_NB]=GR_EGM[key]; GR_BD[GR_NB]=GR_BACK[e]
            continue
        }
        sx = GR_CX[f]; tx = GR_CX[t]; g = GR_LAY[f]
        top = GR_BASE[g] + GR_MAXH[g]
        bot = top + GR_GAPR[g] - 1
        ln = GR_EDU[e] ? "┊" : "│"
        # 兩端的小標記（ER 的基數）緊貼線畫，不要塞進標籤 ——
        # 標籤太長時兩條邊會互相擠掉。mermaid 也是放兩端。
        if (GR_CFM[key] != "") gr_put(top, sx+1, GR_CFM[key])
        if (GR_CTM[key] != "") gr_put(bot, tx+1, GR_CTM[key])
        if (sx == tx) {
            for (r = top; r < bot; r++) gr_v(r, sx, ln)
            GR_G[bot,sx] = "▼"
            if (GR_EGM[key] != "") gr_put(top + 1, sx+2, GR_EGM[key])
            continue
        }
        rb = top + (++GR_USED[g])
        for (r = top; r < rb; r++) gr_v(r, sx, ln)
        lo = sx<tx ? sx : tx; hi = sx>tx ? sx : tx
        GR_G[rb,sx] = (tx>sx) ? "└" : "┘"
        for (x = lo+1; x <= hi-1; x++) gr_h(rb, x)
        GR_G[rb,tx] = (tx>sx) ? "┐" : "┌"
        for (r = rb+1; r < bot; r++) gr_v(r, tx, ln)
        GR_G[bot,tx] = "▼"
        # 標籤置中在跨距上；比跨距長就改放線的右邊 ——
        # 硬置中會把兩端的轉角蓋掉（實測 "┌ 提出" 就是 ┘ 被吃了）。
        if (GR_EGM[key] != "") {
            if (dw(GR_EGM[key]) + 2 <= hi - lo - 1)
                gr_put(rb, lo + int((hi-lo-dw(" " GR_EGM[key] " "))/2) + 1, " " GR_EGM[key] " ")
            else
                gr_put(rb, hi + 2, GR_EGM[key])
        }
    }
    out = ""
    for (r = 1; r <= GR_BASE[GR_MAXL] + GR_MAXH[GR_MAXL] - 1; r++) out = out gr_row(r) "\n"
    # 回邊與跨層邊列在圖下面 —— 硬畫進格子會穿過別人的方塊
    if (GR_NB > 0) {
        out = out "\n"
        for (b = 1; b <= GR_NB; b++)
            out = out sprintf("  %s %s %s%s\n", GR_T[GR_BF[b]],
                              (GR_BD[b] ? "⤴" : "─▶"), GR_T[GR_BT[b]],
                              (GR_BG[b] != "" ? "   (" GR_BG[b] ")" : ""))
    }
    return out
}

# 呼叫端用的小工具：重置節點／邊
function gr_reset(   i) {
    GR_NN = 0; GR_NE = 0
    for (i in GR_T)  delete GR_T[i]
    for (i in GR_B)  delete GR_B[i]
    for (i in GR_BN) delete GR_BN[i]
    for (i in GR_SH) delete GR_SH[i]
    for (i in GR_ID) delete GR_ID[i]
}
function gr_node(key,   i) {
    if (!(key in GR_ID)) {
        GR_NN++; GR_ID[key] = GR_NN; GR_T[GR_NN] = key; GR_BN[GR_NN] = 0; GR_SH[GR_NN] = "["
    }
    return GR_ID[key]
}
function gr_edge(f, t, lab, dot) {
    GR_NE++; GR_F[GR_NE] = f; GR_TO[GR_NE] = t; GR_L[GR_NE] = lab; GR_D[GR_NE] = dot
    GR_CF[GR_NE] = ""; GR_CT[GR_NE] = ""
}
# 帶兩端標記的版本
function gr_edge_c(f, t, lab, dot, cf, ct) {
    gr_edge(f, t, lab, dot)
    GR_CF[GR_NE] = cf; GR_CT[GR_NE] = ct
}
