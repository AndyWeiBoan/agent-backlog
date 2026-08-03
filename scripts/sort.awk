# 待辦的排序。前四個欄位必須是：
#   window_id TAB 狀態 TAB 標題 TAB 優先度
# 後面還有什麼都原樣保留（MCP 的 list 就在後面掛了 pane_current_command
# 與 session_name）—— 這支只重排「列」，不動「行內容」。
#
# 順序：done 沉底 → 優先度降冪 → 標題升冪
#
# 為什麼 done 沉底：做完的項目是純噪音，但刪掉它是另一個決定。
# 沉底讓板子自己保持乾淨，而你想回頭看它還在。
#
# 為什麼最後看標題而不是 window 順序：window 順序是「建立順序」，
# 跟你怎麼命名無關 —— 實測會出現 K0 K1 K2 K9 K3 K4… 這種（K9 比 K3 早建）。
# 而命名本來就帶著意圖，照標題排就等於照你的意圖排，不需要另外標任何東西。
#
# 用插入排序而不是外部 sort：待辦數量是幾十則，n² 完全無感；
# 而且少一個外部指令，也不必處理 BSD sort 與 GNU sort 在 -t 與數值鍵上的差異。

BEGIN { FS = "\t"; OFS = "\t"; n = 0 }

{
    n++
    LINE[n] = $0
    NM[n] = $3
    # 沒設就是 1。+0 會把非數字吃成 0，所以先擋掉再轉。
    P[n] = ($4 ~ /^[0-9]+$/) ? $4 + 0 : 1
    if (P[n] < 1)  P[n] = 1
    if (P[n] > 10) P[n] = 10
    DONE[n] = ($2 == "done") ? 1 : 0
    IDX[n] = n
}

END {
    for (i = 2; i <= n; i++) {
        k = IDX[i]
        j = i - 1
        while (j >= 1 && less(k, IDX[j])) { IDX[j + 1] = IDX[j]; j-- }
        IDX[j + 1] = k
    }
    # 印回原行，但把第 4 欄換成夾過範圍的值 ——
    # 下游（list.awk、MCP 的 list）就不用各自再夾一次。
    for (i = 1; i <= n; i++) {
        k = IDX[i]
        m = split(LINE[k], f, FS)
        f[4] = P[k]
        out = f[1]
        for (c = 2; c <= (m > 4 ? m : 4); c++) out = out OFS (c in f ? f[c] : "")
        print out
    }
}

# a 是否該排在 b 前面
function less(a, b) {
    if (DONE[a] != DONE[b]) return DONE[a] < DONE[b]   # 未完成的在前
    if (P[a]    != P[b])    return P[a]    > P[b]      # 分數高的在前
    return NM[a] < NM[b]                               # 標題（位元組序，見 lib.sh）
}
