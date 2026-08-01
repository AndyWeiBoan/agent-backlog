#!/bin/sh
# 右窗格：反覆從 fifo 讀內容印出來。
# 寫入端關閉時 cat 結束，迴圈重新開啟，等下一次 render。
#
# fifo 不見了就結束 —— 否則 chooser 收尾刪掉暫存目錄之後，
# cat 會立刻失敗並無限重試，變成 100% CPU 的空轉迴圈。
f=$1
while [ -p "$f" ]; do cat "$f"; done
