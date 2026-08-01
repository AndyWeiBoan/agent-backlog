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
| `scripts/preview_pane.sh` | 5 | 預覽窗格：從 fifo 讀內容印出來 |

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
| `@agent_backlog_return` | 開選單前所在的 window（取消時回去） |
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
C-r         重新讀取清單
ESC / C-c   離開，回到開選單前的 window
```

## 效能

每按一鍵的成本（macOS，11 則）：

| | 舊的做法 | 現在 |
|---|---|---|
| tmux round trip | 7～8 次（一次 23.6 ms） | **0 次** |
| 讀鍵 | 每位元組 `dd`+`od`+`tr` | 一次讀整批，7.1 ms |
| 畫清單 | — | 8.0 ms |
| 預覽 | 每鍵重畫 | 只在選中項改變時 |
| **合計** | 約 180 ms | **約 15 ms** |

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
| 清單標題截斷 | 逐位元組的 awk 上用 `length()` 當上界，中文會被高估（一個字算 3 而非 2），只會提早截斷，不會撐爆版面 |
| 表格 | `md.awk` 不 render 表格，要算 East Asian Width |
| 持久化 | 沒有。重開機／tmux server 掛掉就沒了（見 [04](04-roadmap.md) 階段二） |
| 派工 / 刪除 | 尚未接上 |

## 這一輪踩到的坑

全部整理在
[01 的「實作上踩過的坑」](01-current-implementation.md#tmux寫新版時新踩到的)。
四個最貴的：

1. **tmux 3.4 逃逸控制字元**，3.6a 不會 —— 只在 mac 上測絕對看不到
2. **`trap` 沒攔 SIGHUP** —— `kill-window` 送的就是它，收尾完全不跑
3. **搶鍵搶不贏** —— macOS 吃掉 `Ctrl+←→`，使用者 config 吃掉 `Option+←→`
4. **`unset TMUX` 是拆安全鎖** —— 在 session 內部執行會變成自己 attach 自己，
   resize 無窮回饋，畫面抖到剩 1 列
