# 算出「要換哪幾對 window」才能讓 tmux 的 window 順序等於清單順序。
#
# 為什麼需要：清單的排序（見 sort.awk）只影響我們自己畫出來的東西。
# tmux 自己的 window 列表、狀態列、C-b w 全部照 window_index 排 ——
# 它不認識 @agent_backlog_priority。兩個順序不一致的話，
# 從哪個門進來看到的先後就不一樣。
#
# 輸入（兩段，用第一欄的標記分開）：
#   S <TAB> window_index <TAB> window_id     目前的槽位，照 index 遞增
#   D <TAB> window_id                        想要的順序（sort.awk 排好的）
#
# 輸出：每行一組 "indexA indexB"，照順序做 swap-window 就會到位。
#
# 只在「已經被待辦佔住的 index」之間互換 —— 所以非待辦的 window
# （你的 shell、正在跑的 claude、選單自己）一個都不會動，
# index 的空缺也維持原樣。

BEGIN { FS = "\t"; ns = 0; nd = 0 }

$1 == "S" { ns++; SLOT[ns] = $2; AT[ns] = $3; next }
$1 == "D" { nd++; WANT[nd] = $2; next }

END {
    # 只有兩邊是同一組 window 時才動手。
    # 數量不一致代表清單與 tmux 看到的不是同一批（例如中間有 window 被關掉），
    # 這時候什麼都不做比亂換安全 —— 下一次觸發自然會對上。
    if (ns != nd || ns < 2) exit 0

    # 想要的第 i 名應該坐在第 i 個槽位。不在就把它換過來。
    # 選擇排序：每個槽位最多換一次，總共不超過 n-1 次。
    for (i = 1; i <= ns; i++) {
        if (AT[i] == WANT[i]) continue
        j = 0
        for (k = i + 1; k <= ns; k++) if (AT[k] == WANT[i]) { j = k; break }
        if (j == 0) continue          # 找不到就跳過，不要硬換
        print SLOT[i] " " SLOT[j]
        t = AT[i]; AT[i] = AT[j]; AT[j] = t
    }
}
