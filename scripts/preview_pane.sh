#!/bin/sh
# 右窗格：只做一件事 —— 反覆從 fifo 讀內容印出來。
# 寫入端關閉時 cat 結束，迴圈重新開啟，等下一次 render。
#
# fifo 不見了就結束 —— 否則 chooser 收尾刪掉暫存目錄之後，
# cat 會立刻失敗並無限重試，變成 100% CPU 的空轉迴圈。
#
# 關掉回顯：這個窗格不讀鍵也不處理任何輸入。萬一焦點跑過來（滑鼠點、
# prefix o…），使用者打的字會被 tty 直接回顯在畫面上，把預覽內容弄髒。
# chooser 那邊有 hook 會把焦點彈回去，這裡是第二層保險。
stty -echo 2>/dev/null

f=$1
while [ -p "$f" ]; do cat "$f"; done
