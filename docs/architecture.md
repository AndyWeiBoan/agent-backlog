# 架構與不可打破的規則

README 講「這是什麼、怎麼用、有什麼副作用」。這份講**改程式碼之前要知道的事**。

只描述現在的狀態。之前有一批研究與規劃筆記（舊的 Node 版實作、fzf 方案的評估、
roadmap），內容已經不成立，所以刪掉了 —— 想看的話在 git 歷史裡。

## 檔案地圖

```
agent-backlog.tmux        TPM 進入點：檢查平台與 tmux 版本、綁鍵
scripts/
  lib.sh                  option key、ab_items（唯一的清單來源與排序）、狀態/優先度寫入
                          ab_alive（window/pane 還在不在 —— 見規則 13）
  open.sh                 開選單（每個 session 一份）
  chooser.sh              左窗格主迴圈：讀鍵 → 篩選 → 畫清單 → 畫預覽
  preview_pane.sh         右窗格：從 fifo 讀什麼就印什麼
  mirror.sh               右下窗格：把選中那則的畫面即時照過來（見規則 15）
  dispatch.sh             在待辦的 window 裡啟動 agent 並把內容送進去
  home.sh                 回工作區（給全域按鍵用；選單裡的 C-o 走同一套判斷）
  add.sh                  從 shell 新增一則
  backup.sh restore.sh    匯出／還原（唯一的救援手段）
  migrate.sh              舊版 action-items 的資料搬過來
  mcp-server.sh           MCP server（JSON-RPC over stdio），10 個工具
  mcp/json_get.awk        JSON → 路徑<TAB>值（含 \uXXXX 還原）
  mcp/json_str.awk        字串跳脫
  mcp/check.awk           只翻某一個 checkbox 的勾，其他一個字都不動
  width.awk               顯示寬度（East Asian Width）。md.awk 與 list.awk 共用
  sort.awk                清單排序：done 沉底 → 優先度降冪 → 標題
  reorder.awk             算出要換哪幾對 window 才能讓 tmux 的順序等於清單順序
  list.awk                畫整個左窗格
  md.awk                  markdown → ANSI
  graph.awk               分層圖引擎（節點 + 邊 → 字元格）
  seq.awk                 時序圖解析
  flow.awk                流程圖解析（佈局交給 graph.awk）
tools/                    只用來重新產生 README 的圖。plugin 用不到，需要 python3
```

`md.awk` 這一組的呼叫方式是多個 `-f`，而且**必須** `LC_ALL=C`：

```sh
LC_ALL=C awk -f width.awk -f graph.awk -f seq.awk -f flow.awk -f md.awk
LC_ALL=C awk -f width.awk -f list.awk
```

## 不可打破的規則

這些不是風格偏好，每一條都對應一個實際壞過的東西。

（另外：選單記兩個位置。`@agent_backlog_return` 是「按鍵當下在哪」，ESC 回它；
`@agent_backlog_home` 是「最後一次從**不是待辦**的 window 開選單的地方」，`C-o` 回它。
只有一個的話，「工作區 → 選單 → 進待辦 → 選單」之後工作區就沒有任何東西指向它了 ——
它不在清單裡，錨點也被覆蓋掉。細節見 `open.sh`。

`@agent_backlog_home` 只在「從非待辦的 window 開選單」時才寫得到，
而實際上使用者常常整段時間都待在待辦裡按開選單鍵 —— 那它會一直是空的。
所以 `C-o` 一定要有 `ab_workspace()` 這條退路（session 裡第一個非待辦 window），
不然這個功能等於要先用某個特定順序操作一次才會動。）

### 1. `LC_ALL=C` 是必要條件，不是保險

`length()` 回 byte 數還是字元數取決於 awk 實作與 locale ——
macOS 的 BWK awk 在 UTF-8 locale 下 `length("專案") == 6`，gawk 是 2。
`width.awk` 自己解 UTF-8，前提是 byte 模式。改了呼叫方式記得連 `LC_ALL` 一起帶。

### 2. 數字全部用十進位

BWK awk 不認 `0x80` 這種十六進位常值 —— 它解析成 `0` 接一個叫 `x80` 的空變數，
比較永遠成立，UTF-8 解碼會**靜默**歪掉。

### 3. 不要把 ANSI 逃逸碼塞進字元格陣列

`gr_put` / `sq_put` 是一格一個字元，escape 的每個位元組都會佔掉一格。
上色一律在出場時按「這格是不是線條」判斷。同理，量方塊寬度不能對已經上色的字串
用 `dw()`。

### 4. 圖表認不出來就回空字串

`seq_render` / `flow_render` 不認得就回 `""`，`md.awk` 照 code block 畫。
這條讓「加一種圖」和「拿掉一種圖」都不可能弄壞既有的 render ——
最壞情況是看到原始碼。

### 5. 預覽的 render 只能有一個定義

`chooser.sh` 的 `render_item()`。`draw_preview` 產生快取、`poll` 產生 `.new`
拿去 `cmp` —— 兩邊只要有一個位元組不同，poll 就會每 3 秒都認為內容變了而重畫，
畫面會固定閃爍。

### 6. 排序只有一個定義

`lib.sh` 的 `ab_items()`。選單、MCP 的 `list`、`backup` 全部走那一支，
所以人和 agent 看到的順序不可能不一樣。

### 7. 訊號的 trap 一定要自己 `exit`

trap 執行完會繼續往下跑。只寫 `trap cleanup HUP` 等於把「終端機關掉就結束」
拆掉，主迴圈會對著死掉的 tty 空轉（實測：20 個孤兒行程、11% CPU）。

### 8. `key-table` 是 session 層級的，一定要還原

`set -w` / `set -p` 都會被 tmux 悄悄轉成 session。沒還原的話整個 session
從此跳過 root 表，使用者的 `C-p` / `C-t` / `C-d` 全部失效，而且看不出原因。

同一件事的另一面：選單開著的時候 key-table 是 `agent-backlog`，所以**任何想在
選單裡也生效的全域按鍵，兩張表都要綁**（`agent-backlog.tmux` 的 `home_key`）。
只綁 root 的話會變成「在待辦裡按有效、在選單裡按沒效」—— 使用者只會覺得時靈時不靈。

### 9. 不要用空字串當 tmux 的 target

`kill-window -t ""` 對 tmux 來說等於「當前的」—— 會殺掉使用者正在看的 window。

### 10. 別把 session id 放進要 `eval` 的字串

session id 長得像 `$8`。`eval` 會把它當第 8 個位置參數展開
（實測 `'$16:2'` 變成 `'6:2'`）。用位置參數累積再 `tmux "$@"`。

### 11. `swap-window` 會改動「當前 window」

tmux 的當前 window 是記 index 的。`-d` 不解決這件事（它只是換一種挑法）——
要先記下原本的 `window_id`，換完再 `select-window` 選回去。

### 12. 給 agent 的寫入一律是窄的

沒有「整份取代」。`append` 只能追加，`check` 只能翻一個 `[ ]`↔`[x]`，
`delete` 一次一則且必須指名、刪前 stash 進 tmux buffer。
這個系統沒有版本歷史、沒有 undo。

### 13. 不要用 `display -p -t <id>` 判斷它還在不在

實測 tmux 3.6a 對**已經不存在**的 window / pane 一樣回 rc=0（輸出是空的）。
所以 `tmux display -p -t "$id" '' >/dev/null 2>&1 || …` 這種寫法是**假的檢查**，
永遠成立。用 `lib.sh` 的 `ab_alive()` —— 它拿 `list-windows -a` / `list-panes -a`
的實際清單來比對。

被這條咬過兩處：主迴圈「pane 沒了就結束」的保險（等於沒有），
以及 `C-o` 回工作區時對已關閉的目標（會變成殺掉選單然後讓 tmux 亂挑一個 window）。

### 14. 提示列必須真的塞得進它負責的寬度

`list.awk` 的三版提示是按寬度挑的，門檻用 `dw()` 現算，不寫死數字。
寫死過一次 96，但長版其實是 158（中）／173（英）欄 ——
96～172 欄的窗格一路看到被切一半的提示。
只有最短的那版要自己保證 ≤ 40（`chooser.sh` 允許的最小窗格）。

### 15. 鏡像窗格只能垂直切，而且不要自己算截斷

`sync_mirror` 用 `split-window -v`。**水平切會改變預覽的寬度**，
而 `md.awk` 的表格與 code block 框線是按寬度算的 —— `measure()` 會發現寬度變了，
把整批 render 快取丟掉重畫。垂直切只動高度，快取全部有效。

截斷交給終端機（`mirror.sh` 關掉 DECAWM），不要自己按顯示寬度切：
`capture-pane -e` 的輸出夾著 SGR 逃逸碼，逐欄截斷得先解析它們，
否則不是把顏色切壞就是把逃逸碼算進欄數。

另外 `capture-pane` 拿到的是來源**已經排版好的格線**，不會為了這裡的寬度重排。
所以來源比鏡像寬的話右邊就是會被切掉 —— 這是機制本身的上限，不是 bug。

### 16. `sync_mirror` 動到版面時一定要強迫重畫

高度變了但內容沒重印的話，上半部的 copy-mode 還停在舊高度算出來的捲動範圍。
`draw_preview` 是「先 sync 再寫內容」所以沒事；`poll` 不寫內容，
那邊改完版面一定要 `LAST_ID=""; DIRTY=1`。

驗證捲動**不能用 `capture-pane`** —— 它抓的是底層螢幕，不是 copy-mode 正在顯示的畫面。
要看 `#{scroll_position}`（等於 `#{history_size}` 就是停在頂端）。

## 改完之後要驗什麼

1. **三種 awk 輸出逐位元組相同** —— BWK 20200816（macOS）、gawk、busybox。
   Alpine 容器裡兩種都有。
2. **不相關的內容輸出不能變。** 動 renderer 的時候，拿一批不含該語法的內容
   比對前後輸出，必須逐位元組相同。
3. **多種寬度。** 至少 30 / 60 / 100 —— 折行與截斷的 bug 只在窄的時候出現。
4. **中文。** 每一個寬度計算的 bug 都是中文才看得出來。
