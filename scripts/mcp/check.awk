# 翻某一個 checkbox 的勾，其他一個字都不動。
#
# 變數：idx（第幾個 checkbox，1-based，0 = 不用）
#       match_(子字串比對，idx 為 0 時使用)
#       done_（1 = 打勾、0 = 取消打勾）
#       rf（把結果摘要寫到這個檔：changed<TAB>行內容）
#
# 為什麼是這種窄工具，而不是給 agent 一個「整份取代」的 update：
# 這個系統沒有版本歷史、沒有 undo，內容就活在 tmux 記憶體裡。
# 整份取代等於一次呼叫就能洗掉使用者寫的所有東西。
# 這支只能把 [ ] 換成 [x]（或反過來），連同一行的文字都不會動到。

BEGIN { n = 0; changed = 0 }

{
    line = $0
    if (line ~ /^[ \t]*[-*] \[[ xX]\] /) {
        n++
        hit = 0
        if (idx > 0) {
            if (n == idx) hit = 1
        } else if (match_ != "" && index(line, match_) > 0) {
            hit = 1
        }
        if (hit && !changed) {
            # 只換方括號裡那一個字元，位置由 match 找出來，不用重組整行
            if (match(line, /\[[ xX]\]/)) {
                line = substr(line, 1, RSTART) (done_ ? "x" : " ") \
                       substr(line, RSTART + 2)
                changed = 1
                print "1\t" line > rf
            }
        }
    }
    print line
}

END {
    if (!changed) print "0\t" > rf
}
