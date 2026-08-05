# C4：mermaid C4Context / C4Container / C4Component → 文字
#
# C4 的結構是「邊界裡面裝元素」—— 那是巢狀方塊，不是圖佈局。
# 所以這支不需要分層也不需要繞線：遞迴算出每一塊的寬度再往外包就好。
# Rel() 列成關係表 —— 硬畫連線會穿過方塊。
#
# 認不出來就回 ""。依賴 width.awk。全域一律 C4_ 前綴。

function c4_pad(s, n,   o) { o = s; n -= dw(s); while (n-- > 0) o = o " "; return o }
function c4_dn(n,   o) { o = ""; while (n-- > 0) o = o "─"; return o }

# ⚠️ 可見寬度要當參數傳進來，不能用 dw(s) 量 —— s 裡面有 ANSI 逃逸碼，
# dw() 會把那些位元組也算成寬度，外層的框就會歪掉（實測邊界右框線會亂跳）。
function c4_put(i, s, vw) {
    C4_LN[i, ++C4_NL[i]] = s
    if (vw > C4_WD[i]) C4_WD[i] = vw
}

# 元素：一個方塊，名稱 / [型別] / 說明
function c4_leaf(i,   w, ty) {
    ty = "[" C4_TY[i] "]"
    w = dw(C4_LB[i])
    if (dw(ty) > w) w = dw(ty)
    if (dw(C4_DS[i]) > w) w = dw(C4_DS[i])
    c4_put(i, "┌─" c4_dn(w) "─┐", w + 4)
    c4_put(i, "│ " C4_B c4_pad(C4_LB[i], w) C4_R " │", w + 4)
    c4_put(i, "│ " C4_D c4_pad(ty, w) C4_R " │", w + 4)
    if (C4_DS[i] != "") c4_put(i, "│ " C4_D c4_pad(C4_DS[i], w) C4_R " │", w + 4)
    c4_put(i, "└─" c4_dn(w) "─┘", w + 4)
}

# 邊界：子節點各自畫好之後取最寬的當 inner，
# 每一列是 "│ " + 子節點(補到 inner) + " │"，所以這個框的可見寬度是 inner + 4。
# 上下框線都照這個算，不然右邊會歪。
function c4_box(i,   c, j, k, inner) {
    inner = 0
    for (c = 1; c <= C4_NC[i]; c++) {
        j = C4_CH[i, c]
        if (C4_TY[j] == "BOUNDARY") c4_box(j); else c4_leaf(j)
        if (C4_WD[j] > inner) inner = C4_WD[j]
    }
    if (dw(C4_LB[i]) > inner) inner = dw(C4_LB[i])
    c4_put(i, "╭╴" C4_B C4_LB[i] C4_R "╶" c4_dn(inner - dw(C4_LB[i])) "╮", inner + 4)
    for (c = 1; c <= C4_NC[i]; c++) {
        j = C4_CH[i, c]
        for (k = 1; k <= C4_NL[j]; k++)
            c4_put(i, "│ " C4_LN[j, k] c4_pad("", inner - C4_WD[j]) " │", inner + 4)
        if (c < C4_NC[i]) c4_put(i, "│" c4_pad("", inner + 2) "│", inner + 4)
    }
    c4_put(i, "╰" c4_dn(inner + 2) "╯", inner + 4)
}

function c4_render(buf, n,   bi, line, kind, args, na, A, i, j, k, c, sp, root,
                   out, seen, a, b, w1) {
    C4_R = sprintf("%c[0m", 27)
    C4_B = sprintf("%c[1m", 27)
    C4_D = sprintf("%c[2m", 27)
    C4_NN = 0; C4_NR = 0; seen = 0; sp = 0
    for (i in C4_NL)    delete C4_NL[i]
    for (i in C4_LN)    delete C4_LN[i]
    for (i in C4_WD)    delete C4_WD[i]
    for (i in C4_NC)    delete C4_NC[i]
    for (i in C4_ALIAS) delete C4_ALIAS[i]
    C4_NN++; C4_TY[C4_NN] = "BOUNDARY"; C4_LB[C4_NN] = ""; root = C4_NN
    C4_STK[0] = root

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

        if (kind ~ /Rel/) {
            C4_NR++; C4_RA[C4_NR]=A[1]; C4_RB[C4_NR]=A[2]; C4_RL[C4_NR]=A[3]
            C4_RT[C4_NR]=(na >= 4 ? A[4] : ""); C4_RBI[C4_NR]=(kind ~ /^BiRel/)
            seen = 1; continue
        }
        C4_NN++
        C4_ALIAS[A[1]] = C4_NN
        C4_NC[C4_NN] = 0
        if (kind ~ /Boundary$/) {
            C4_TY[C4_NN] = "BOUNDARY"; C4_LB[C4_NN] = (na >= 2 ? A[2] : A[1])
            C4_CH[C4_STK[sp], ++C4_NC[C4_STK[sp]]] = C4_NN
            sp++; C4_STK[sp] = C4_NN
        } else {
            C4_TY[C4_NN] = kind; C4_LB[C4_NN] = (na >= 2 ? A[2] : A[1])
            # Container / Component 的第 3 個參數是技術，第 4 個才是說明
            if (kind ~ /^(Container|Component)/ && na >= 4) {
                C4_TY[C4_NN] = kind ": " A[3]; C4_DS[C4_NN] = A[4]
            } else C4_DS[C4_NN] = (na >= 3 ? A[3] : "")
            C4_CH[C4_STK[sp], ++C4_NC[C4_STK[sp]]] = C4_NN
        }
        seen = 1
    }
    if (!seen || C4_NC[root] == 0) return ""

    out = ""
    # 最外層不畫框，直接把子節點一個個吐出來
    for (c = 1; c <= C4_NC[root]; c++) {
        j = C4_CH[root, c]
        if (C4_TY[j] == "BOUNDARY") c4_box(j); else c4_leaf(j)
        for (k = 1; k <= C4_NL[j]; k++) out = out C4_LN[j, k] "\n"
        if (c < C4_NC[root]) out = out "\n"
    }
    if (C4_NR > 0) {
        w1 = 0
        for (k = 1; k <= C4_NR; k++) {
            a = (C4_RA[k] in C4_ALIAS) ? C4_LB[C4_ALIAS[C4_RA[k]]] : C4_RA[k]
            b = (C4_RB[k] in C4_ALIAS) ? C4_LB[C4_ALIAS[C4_RB[k]]] : C4_RB[k]
            C4_AA[k] = a; C4_BB[k] = b
            if (dw(a) > w1) w1 = dw(a)
        }
        out = out "\n" C4_B "關係" C4_R "\n"
        for (k = 1; k <= C4_NR; k++)
            out = out sprintf("  %s %s %s%s%s\n",
                        c4_pad(C4_AA[k], w1),
                        (C4_RBI[k] ? "◀─▶" : " ─▶"), C4_BB[k],
                        (C4_RL[k] != "" ? "   " C4_RL[k] : ""),
                        (C4_RT[k] != "" ? C4_D " [" C4_RT[k] "]" C4_R : ""))
    }
    return out
}
