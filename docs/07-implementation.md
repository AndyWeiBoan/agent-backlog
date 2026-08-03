# 07 — 零依賴版本的實作

2026-08-01 寫出來的最小可動版本。**取代**了 `action-items` 的 Node 實作路線。

## 為什麼長這樣

原本的規劃（見 [04](04-roadmap.md)）是用 `choose-tree` 當清單。實測後被三個需求否決：

| 需求 | `choose-tree` | 現在的做法 |
|---|---|---|
| 預覽可捲動 | ❌ 沒有垂直捲動鍵 | 預覽窗格進 copy-mode，從選單窗格 `send-keys -X` 驅動 |
| 模糊搜尋 | ❌ 只有 format 過濾 | awk `index()` 子字串比對 |
| resize 重排 | ❌ 顯示的是既有畫面 | hook 觸發重印 |

一度考慮回頭用 fzf（三項都滿足），但那違背零依賴的目標。最後的解法是
**把 tmux 當 UI 元件用**：捲動與折行交給 copy-mode，我們只負責讀鍵、過濾、印字。

## 檔案

| 檔案 | 行 | 做什麼 |
|---|---|---|
| `agent-backlog.tmux` | 10 | TPM 入口，綁 `prefix + A` |
| `scripts/md.awk` | 155 | markdown → ANSI |
| `scripts/chooser.sh` | 約 190 | 選單迴圈：讀鍵、過濾、畫清單、驅動預覽 |
| `scripts/list.awk` | 77 | 過濾 ＋ 畫整個左窗格 |
| `scripts/lib.sh` | 30 | option key 定義、清單查詢 |
| `scripts/migrate.sh` | 17 | 舊 key → 新 key（不刪舊的） |
| `scripts/open.sh` | 12 | 入口：開 backlog window |
| `scripts/add.sh` | 10 | 建立待辦 |
| `scripts/dispatch.sh` | 60 | 派工：啟動 claude 並把內容貼進去 |
| `scripts/preview_pane.sh` | 5 | 預覽窗格：從 fifo 讀內容印出來 |
| `scripts/mcp-server.sh` | 約 190 | MCP server（stdio JSON-RPC），給 agent 用 |
| `scripts/mcp/json_get.awk` | 140 | JSON → `路徑<TAB>值`，含 `\uXXXX` 還原 |
| `scripts/mcp/json_str.awk` | 14 | 字串 → JSON 跳脫 |

依賴：`tmux` `sh` `awk` `stty` `dd` `od` `sed` `cut` `mkfifo` —— 全部 POSIX。
沒有 node、python、fzf、jq。

## 架構

```
[backlog] window
├── 左窗格  chooser.sh    讀鍵 → awk 過濾 → 印清單
└── 右窗格  preview_pane  while [ -p fifo ]; do cat fifo; done
                          ↑ chooser 把 md.awk 的輸出寫進 fifo
                          ↑ 然後 copy-mode + history-top 捲到頂
```

捲動時 chooser 只送 `tmux send-keys -t <右窗格> -X page-down` ——
**折行、CJK 寬度、捲動指示器 `[n/m]` 全部是 tmux 在做。**

## 資料

沿用「一則待辦 = 一個 window」，只是 key 加了 namespace：

| option | 存什麼 |
|---|---|
| `@agent_backlog_prompt` | 原始 markdown（`dispatch` 要拿它當 prompt） |
| `@agent_backlog_status` | pending / running / blocked / done |
| `@agent_backlog_cursor` | 目前選中的 window_id（給 hook 讀，hook 是另一個行程） |
| `@agent_backlog_return` | 開選單前所在的 window（取消時回去）。**session 層級**，各 session 各記各的 |
| `@agent_backlog_width` | 左窗格寬度（記住使用者調過的） |

## 鍵位

```
打字        篩選（index() 子字串，中文可用）
↑ ↓         選擇（C-n / C-p 同）
C-e / C-y   預覽捲一行
C-d / C-u   預覽捲半頁
C-f / C-b   預覽捲整頁
prefix+⌥←→  調整分隔線寬度（tmux 原生，我們靠 hook 得知）
Enter       切到該待辦
C-g         派工
C-t         輪替狀態
C-x         刪除（先問 y/n）
C-r         重新讀取清單
ESC / C-c   離開，回到開選單前的 window
```

## 鍵位為什麼能這樣用

因為選單那個 window 設了 `key-table`：

```sh
tmux set-option -w -t "$MYWIN" key-table agent-backlog
```

指到一張**不存在**的表 = 什麼都沒綁 = 所有按鍵直接落到程式手上。
沒有這行的話，使用者 `~/.tmux.conf` 裡任何 `bind -n` 都會先攔走
（實際遇到的：`C-d` 開分割、`C-p` 選 session、`C-t` 開新 window、
`C-s` 分割、`C-w` 殺 pane、`M-方向鍵` 切窗格）。

挑鍵閃避是沒有用的 —— 下一台機器就是另一組 config。`prefix` 不受影響，
所以 `prefix + ⌥←→` 調寬度、`prefix d` 卸離都還能用。

⚠️ **但 `key-table` 是 session 層級的**（`set -w` / `set -p` 都會被轉成 session），
它不會隨著我們的 window 消失。所以要：

1. 啟動時存舊值，離開時還原（`cleanup` 裡做）
2. 掛 `after-select-window` hook —— 使用者在選單開著時切到別的 window，
   root 表要還回去，切回來再拿走

漏掉第 1 點的後果是：關掉選單之後使用者的 `C-p` `C-t` `C-d` 全部失效，
而且看不出跟這個 plugin 有關。

## MCP 也是零依賴的

MCP 的 stdio transport 就是換行分隔的 JSON-RPC 2.0。難點不在協定，在 JSON：

| | 難度 |
|---|---|
| **產生** JSON | 容易。跳脫規則固定，非 ASCII 原樣輸出（JSON 本來就是 UTF-8），中文完全不用特別處理 |
| **解析** JSON | 真問題。但我們只需要 `.id` `.method` `.params.name` `.params.arguments.*` 這幾個路徑，範圍有界 |

`json_get.awk` 是個小型 tokenizer，把一行 JSON 攤平成 `路徑<TAB>值`。
一個必須做對的地方是 **`\uXXXX` 還原**：有些 client（Python 的 `json.dumps`
預設 `ensure_ascii=True`）會把中文全部逃逸，不還原的話整段內容變問號。
碼位轉 UTF-8 在 gawk（逐字元）與 BWK/busybox（逐位元組）行為不同，
所以用 `length("錢")==1` 分流。

實測：中文、emoji（含代理對）、引號、反引號、反斜線、換行，
在三種 awk 上都能完整往返，並且**用真的 Claude Code client 驗過握手與帶參數的呼叫**。

## 效能

每按一鍵的成本（macOS，11 則）：

| | 舊的做法 | 現在 |
|---|---|---|
| tmux round trip | 7～8 次（一次 23.6 ms） | **0 次** |
| 讀鍵 | 每位元組 `dd`+`od`+`tr` | 一次讀整批，7.1 ms |
| 畫清單 | — | 8.0 ms |
| 預覽 | 每鍵重畫 | 只在選中項改變時 |
| **合計** | 約 180 ms | **約 15 ms** |

resize 另外做了防抖 —— 拖曳分隔線、連按 `⌥←→`、縮放終端機都是**連續事件**，
每一步都重畫會閃個不停。做法是收到 resize 訊號時只記旗標，
接著用 100 ms 的逾時讀把後續事件吸收掉，安靜下來才量一次、畫一次。
實測 17 個觸發事件（開場 1 ＋ ⌥→ 8 次 ＋ resize 8 次）只重畫 6 次，
其中連續 8 次視窗 resize 完全合併成 1 次。

三個關鍵決定：

1. **尺寸只在啟動與 resize 時量** —— 一次 tmux round trip 要 23.6 ms，每鍵問兩次就毀了
2. **清單快取在檔案裡** —— 只有 `C-r` 才重新查 tmux
3. **選中項沒變就不重畫預覽** —— 打字時最花時間的就是它

## 驗證過的環境

| | macOS | Alpine |
|---|---|---|
| tmux | 3.6a | 3.4 |
| shell | zsh / sh | busybox ash |
| awk | BWK 20200816 | busybox 1.36.1（gawk 也測過） |
| 結果 | ✅ | ✅ |

`md.awk` 在三種 awk 實作下輸出**逐字元相同**，連 ANSI 都一致。

## 已知限制

| | 狀況 |
|---|---|
| code block 框線 | 寬度由 chooser 把預覽窗格寬度傳給 `md.awk`（`-v w=`）。resize 後 render 快取要作廢重畫，否則框線停在舊寬度 |
| 清單標題截斷 | 逐位元組的 awk 上用 `length()` 當上界，中文會被高估（一個字算 3 而非 2），只會提早截斷，不會撐爆版面 |
| 表格 | `md.awk` 不 render 表格，要算 East Asian Width |
| 持久化 | 沒有。重開機／tmux server 掛掉就沒了（見 [04](04-roadmap.md) 階段二） |
| 派工 | 需要 `claude` 在**那個 pane 的互動 shell** 的 PATH 裡（`run-shell` 繼承的是 tmux server 當初的 PATH，不是 pane 的） |

## 這一輪踩到的坑

全部整理在
[01 的「實作上踩過的坑」](01-current-implementation.md#tmux寫新版時新踩到的)。
四個最貴的：

1. **tmux 3.4 逃逸控制字元**，3.6a 不會 —— 只在 mac 上測絕對看不到
2. **`trap` 沒攔 SIGHUP** —— `kill-window` 送的就是它，收尾完全不跑
3. **搶鍵搶不贏** —— macOS 吃掉 `Ctrl+←→`，使用者 config 吃掉 `Option+←→`
4. **`unset TMUX` 是拆安全鎖** —— 在 session 內部執行會變成自己 attach 自己，
   resize 無窮回饋，畫面抖到剩 1 列
