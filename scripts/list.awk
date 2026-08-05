# 畫整個左窗格：查詢列、計數、清單、底部提示。一支 awk 印完，不另外開行程。
#
# 輸入：ab_items 的輸出（window_id TAB 狀態 TAB 標題 TAB 優先度）
#       —— 已經排序好了（見 sort.awk），這裡只負責篩選與畫，不重排。
# 變數：q（查詢原文，awk 自己轉小寫）、cur（游標，1-based）、w（欄寬）、h（欄高）、
#       total（總則數）、mf（命中清單輸出檔）
#
# 比對用 index() 子字串，不是逐字元子序列 —— 因為 BWK awk 與 busybox awk 是
# 逐位元組的（length("錢")=3，只有 gawk 給 1），逐字元拆會把一個中文字拆成
# 三個位元組。index() 在位元組層級對 UTF-8 是正確的。

# raw 模式下 ONLCR 是關的，換行要自己補 CR。
# 不能用 ORS —— 它只作用在 print，而 print 在這裡是寫命中檔給 sh 讀的，
# 補了 CR 會污染資料。
BEGIN {
    US  = sprintf("%c", 9)      # tab，見 lib.sh 的說明
    E   = sprintf("%c[", 27)
    R   = E "0m"
    SEL = E "7m"                # 反白：選中那行
    DIM = E "2m"
    # 狀態的顏色。亮度大致對應「這件事有多需要你」——
    # 卡住的最刺眼，做完的最安靜，待做的維持可讀但不搶戲。
    #
    # 狀態本身是任意字串（set_status 不限制），所以一定要有 fallback，
    # 不能寫成 if/else 兩條路。
    ST_PEND  = E "38;5;250m"      # pending：淺灰，最多的那一種，不該吵
    ST_RUN   = E "38;5;214m"      # running：橘，正在發生的事
    ST_BLOCK = E "1;38;5;196m"    # blocked：粗體亮紅，要你去處理
    ST_DONE  = E "2;38;5;108m"    # done：暗綠，已經沉到底部了，安靜
    ST_OTHER = E "38;5;250m"      # 自訂狀態
    OK  = E "38;5;108m"
    # 優先度與狀態是兩個不同的軸，而且欄位貼在一起 —— 各自用一個色系才分得開。
    # 優先度走藍：同一個色相，靠亮度表示高低。
    # 紅色留給 blocked（見下面）—— 原本優先度 7+ 也用粗紅，跟它擠在一起看不出差別。
    PRI = E "38;5;110m"         # 優先度 2-6：淡藍，存在但不搶眼
    PRIH= E "1;38;5;45m"        # 優先度 7-10：粗體亮青，一眼看到但不跟 blocked 搶
    EL  = E "K"                 # 清到行尾
    CHARAWARE = (length("錢") == 1)   # 這台的 awk 是逐字元還是逐位元組
    # 介面文字。預設英文；lang=zh 切繁中。
    if (lang == "zh") {
        T_ITEMS = "則"
        T_THIS  = "· 本 session（Tab 看全部）"
        T_ALL   = "· 全部 session（Tab 切回本 session）"
        T_EMPTY = "沒有符合的待辦"
        T_HINT  = " ↑↓ 選擇  打字篩選（標題或 @id）  捲預覽 C-e/C-y·C-d/C-u·C-f/C-b  Enter 切過去  C-g 派工  C-t 狀態  C-k/C-j 優先度  C-x 刪除  Tab 範圍  ESC 離開"
        T_HINT2 = " ↑↓ 選擇 · C-e/C-y 捲預覽 · Enter 切過去 · ESC 離開"
    } else {
        T_ITEMS = "items"
        T_THIS  = "· this session (Tab: all)"
        T_ALL   = "· all sessions (Tab: this one)"
        T_EMPTY = "no matching items"
        T_HINT  = " ↑↓ select   type to filter (title or @id)   C-e/C-y scroll   Enter switch   C-g dispatch   C-t status   C-k/C-j priority   C-x delete   Tab scope   ESC quit"
        T_HINT2 = " ↑↓ select · C-e/C-y scroll · Enter switch · ESC quit"
    }
    ql = tolower(q)
    n = 0
    rows = h - 4                # 扣掉查詢列、計數列、空行、提示列
    if (rows < 1) rows = 1
}

{
    split($0, f, US)
    # 標題比對，外加 window_id。
    #
    # agent 在對話裡是用 window_id 指某一則的（「@355 自己標它是最大的不確定性」），
    # 而那串數字在清單上沒有出現過 —— 使用者對不起來。
    # 讓 id 也能被搜到，打 355 或 @355 都會只剩那一則。
    # f[1] 是 @355 這種格式，本來就沒有大小寫。
    if (ql != "" && index(tolower(f[3]), ql) == 0 && index(f[1], ql) == 0) next
    n++
    print $0 > mf
    sts[n] = (f[2] == "" ? "-" : f[2])
    tis[n] = f[3]
    prs[n] = (f[4] ~ /^[0-9]+$/) ? f[4] + 0 : 1
}

END {
    # 不清整個畫面 —— \033[2J 每按一鍵閃一次。
    # 改成游標歸位、逐行清到行尾，最後再清掉底下殘留。
    printf "%sH", E
    out(RUN "❯" R " " q DIM "▏" R)
    out(sprintf("  %s%d/%d %s%s  %s%s%s", DIM, n, total, T_ITEMS, R,
                DIM, (scope == "global" ? T_ALL : T_THIS), R))
    out("")

    if (n == 0) {
        out(DIM "  " T_EMPTY R)
    } else {
        top = (cur > rows) ? cur - rows + 1 : 1   # 讓游標留在可視範圍內
        for (i = top; i <= n && i < top + rows; i++) {
            # 優先度、狀態都在前、都是固定寬純 ASCII —— 不需要算 East Asian Width。
            # 標題放最後，中文再長也不會把後面的欄位推歪。
            #
            # 優先度 1（預設）不印數字。大部分待辦都是 1，每行都印一個「1」
            # 只是噪音；留白本身就表示「沒有特別指定」。
            p = (prs[i] > 1) ? sprintf("%2d", prs[i]) : "  "
            title = cutw(tis[i], w - 15)
            if (i == cur)
                out(SEL pad(sprintf(" %s %-8s %s", p, sts[i], title), w - 1) R)
            else
                # done 的標題也一起變暗 —— 它已經沉到底部了，
                # 只有狀態欄變色的話，那幾行的標題還是跟未完成的一樣亮。
                out(sprintf(" %s%s%s %s%-8s%s %s%s%s",
                            (prs[i] >= 7 ? PRIH : PRI), p, R,
                            stcolor(sts[i]), sts[i], R,
                            (sts[i] == "done" ? DIM : ""), title,
                            (sts[i] == "done" ? R : "")))
        }
    }
    printf "%sJ", E

    # 最後一列：窄的時候用短版提示。長版在一般寬度（左窗格約 50 欄）會被切掉，
    # 切一半的提示比沒有提示更糟 —— 看起來像壞掉。
    # 最後一列：寫到最後一格會讓終端機捲一行，把查詢列頂掉。
    # 關掉自動換行（DECAWM）再寫，超出的直接被丟掉，就完全不用算顯示寬度 ——
    # 正好繞開 awk 算不了 East Asian Width 的老問題。
    printf "%s?7l%s%d;1H%s%s%s%s?7h", E, E, h, DIM,
           (w >= 96 ? T_HINT : T_HINT2), R, E
}

function out(s) { printf "%s%s\r\n", s, EL }

function stcolor(s) {
    if (s == "pending") return ST_PEND
    if (s == "running") return ST_RUN
    if (s == "blocked") return ST_BLOCK
    if (s == "done")    return ST_DONE
    return ST_OTHER
}

# 依顯示寬度截斷。
# 逐位元組的 awk 上用 length() 當上界 —— 中文會被高估（一個字算 3 而不是 2），
# 所以只會提早截斷，不會撐爆版面。精算寬度是之後的事。
function cutw(s, max,   i, o, wsum, c) {
    if (max < 4) max = 4
    if (!CHARAWARE) {
        if (length(s) <= max) return s
        return substr(s, 1, max - 1) "…"
    }
    wsum = 0; o = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        wsum += (c ~ /^[ -~]$/) ? 1 : 2
        if (wsum > max) return o "…"
        o = o c
    }
    return o
}

function pad(s, k) {
    while (length(s) < k) s = s " "
    return s
}
