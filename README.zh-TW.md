# agent-backlog

**人與 AI agent 共享的待辦清單 —— 長在 tmux 裡。**

繁體中文 · [English](README.md)

零依賴。沒有資料庫、沒有 JSON 檔、沒有 Node、沒有 Python、不需要 `fzf`、不需要 `jq`。
只用 tmux 和你機器上本來就有的 POSIX 工具。

```
❯ kyc                                    │ █ Prod: KYC 縮圖遺失
  2/11 則 · 本 session（Tab 看全部）      │
                                         │ ┃ 現象
▌pending   prod-kyc-thumbnail-missing    │ ● prod，7d 82 筆
 blocked   prod-kyc-review-queue-stuck   │ ● 審核頁開不了圖
                                         │
                                         │ ┌─ sql ──────────────────────────────
                                         │ │ SELECT t."PlayerId", t."Total"
                                         │ │ FROM dbo."KycDocument" AS t
                                         │ └────────────────────────────────────
 ↑↓ 選擇  C-e/C-y 捲預覽  Enter 切過去   │
```

---

## 一句話說完核心

> **一則待辦，就是一個 tmux window。**

window 名稱是標題，內容存在 window 的 option 上。整個資料模型就這樣 ——
清單**就是**你的 window 列表，只是濾過。

所以「待辦」和「執行它的地方」是**同一個物件**。不是一筆記錄指向某個工作區，
而是根本就沒有記錄，只有工作區本身。

- 按 `Enter` —— 不是「打開一筆記錄」，是**走進那個 window**
- 按 `C-g` —— 一個 Claude Code 實例**就在那個 window 裡**啟動，用待辦內容當 prompt
- agent 的 `list` 回報的「裡面在跑什麼」是即時查 tmux 得到的事實
  （`zsh` = 還沒開始），不是一個會跟現實脫節的狀態欄位

## 為什麼需要它

跟 AI agent 一起工作時，待辦事項會不斷冒出來。你需要一份**兩邊都看得到**的清單，
裡面的項目可以**交給獨立的 agent 實例執行**，而且你隨時能**親手接手**。

Claude Code 內建的 TodoWrite 做不到這件事 —— 那是單一 session 內的步驟追蹤。
這是另一種東西：活得比 session 久、人抓得到、而且長在工作發生的地方。

## 需求

- **macOS 或 Linux**（其他平台在載入時就會被擋下）
- **tmux 3.0 以上** —— 實測過 3.4 與 3.6a

就這樣。只用到 `sh` `awk` `sed` `stty` `dd` `od` `cut` `tr` `wc` `grep`
`mkfifo` `mktemp` —— 全是 POSIX，你的機器上都有。

## 安裝

### TPM

```tmux
set -g @plugin 'AndyWeiBoan/agent-backlog'
run '~/.tmux/plugins/tpm/tpm'
```

然後 `prefix + I`。

> TPM 自己需要 `bash` 和 `git`。那是 TPM 的依賴，不是本 plugin 的 ——
> 下面「手動」那條路兩個都不需要。

### 手動

```tmux
run-shell ~/path/to/agent-backlog/agent-backlog.tmux
```

然後 `tmux source-file ~/.tmux.conf`。

> `source-file` **不會**移除你已經從設定檔刪掉的 binding。
> 換鍵的話要自己 `tmux unbind <舊鍵>`。

### 給 agent 用（選配）

```sh
claude mcp add agent-backlog -- sh ~/path/to/agent-backlog/scripts/mcp-server.sh
```

MCP server **也是零依賴的** —— POSIX `sh` + `awk`，連 JSON 解析器都是自己寫的。
細節見[運作方式](#運作方式)。

## 用法

`prefix + A` 開清單。（大小寫都綁了 —— tmux 的鍵區分大小寫，只綁 `A` 的話
按 `a` **完全不會有任何反應**，而且沒有錯誤訊息。）

| 鍵 | 動作 |
|---|---|
| *打字* | 篩選（子字串比對，中文可用） |
| `↑` `↓` | 移動選擇（`C-p` / `C-n` 同） |
| `C-e` `C-y` | 預覽捲一行 |
| `C-d` `C-u` | 預覽捲半頁 |
| `C-f` `C-b` | 預覽捲整頁 |
| `Enter` | 切到該待辦的 window |
| `C-g` | 派工：在那裡啟動 `claude` 並把內容貼進去 |
| `C-t` | 輪替狀態（pending → blocked → done） |
| `C-x` | 刪除（先問 `y`/`n`） |
| `Tab` | 切換範圍：本 session ⇄ 全部 session |
| `C-r` | 重新讀取清單 |
| `ESC` `C-c` | 離開，回到開清單之前的位置 |
| `prefix` + `⌥←` `⌥→` | 調整中間分隔線（tmux 原生綁定，寬度會記住） |

從 shell 新增一則：

```sh
echo '## 現象
prod 上 KYC 縮圖開不出來，7d 82 筆。' \
  | sh scripts/add.sh prod-kyc-thumbnail-missing
```

備份／還原（待辦活在 tmux server 記憶體裡，見[取捨與副作用](#取捨與副作用)）：

```sh
sh scripts/backup.sh              # → ~/agent-backlog-<時間>.dump
sh scripts/restore.sh <檔名>       # 已存在的同名會跳過
```

## 設定

| option | 預設 | 說明 |
|---|---|---|
| `@agent_backlog_key` | `A` | `prefix` 之後的鍵 |
| `@agent_backlog_root_key` | — | 不需要 prefix 的鍵，空白分隔可多個 |
| `@agent_backlog_no_key` | — | `on` = 完全不綁，自己來 |
| `@agent_backlog_scope` | `session` | `session` 或 `global` |
| `@agent_backlog_compat` | — | `on` = 連舊版的 `@prompt` / `@status` 一起認 |

想用 `Ctrl+/` 這種不需要 prefix 的鍵：

```tmux
set -g @agent_backlog_root_key 'C-/ C-_'
```

> **兩個都要綁。** extended keys（CSI u）關閉時，終端機對 `Ctrl+/` 送出的
> 其實是 `0x1F`，tmux 認作 `C-_`。只綁 `C-/` 在多數終端機按了沒反應。

自己綁的話，記得把 `#{session_id}` 帶上 —— `run-shell` 會在按鍵當下展開它：

```tmux
set -g @agent_backlog_no_key on
bind-key -n C-o run-shell "sh #{@agent_backlog_path}/scripts/open.sh '#{session_id}'"
```

## 給 agent 用（MCP）

六個工具：`list` `show` `add` `dispatch` `peek` `set_status`。

**刻意沒有 `delete`** —— 刪除是人的動作。

註冊成 MCP 買到的是**可發現性**，不是功能：同樣的事 shell script 就做得到，
但新開的 Claude Code session 根本不知道那些 script 存在。註冊之後每個 session
啟動就自動載入工具與說明。

agent 跟你用同樣的範圍規則 —— 它從繼承來的 `TMUX_PANE` 反推自己在哪個 session。
少了這一步，你看到 0 則、agent 看到 11 則，那就違背這個專案存在的唯一理由。

## 運作方式

**儲存就是 tmux 本身。** 每則待辦是一個 window，帶兩個 user option：

| option | 存什麼 |
|---|---|
| `@agent_backlog_prompt` | 原始 markdown（也就是派工用的 prompt） |
| `@agent_backlog_status` | pending / running / blocked / done（任意字串） |

「這是不是待辦」== 「這個 window 有沒有 prompt option」。不用同步，沒有第二份事實。

**介面是一個 window 切成兩個窗格。** 左邊是 POSIX shell 迴圈，用 `stty raw` + `dd`
讀鍵、用 `awk` 過濾、自己畫清單；右邊是預覽窗格，內容透過 fifo 餵進去。

**捲動交給 tmux。** 預覽窗格停在 copy-mode，選單只負責送 `send-keys -X page-down`。
折行、東亞字元寬度、`[n/m]` 捲動指示器全部是 tmux 的工作 —— 所以免費就正確。

**markdown render 是 169 行 awk**（`md.awk`）—— 標題、清單、行內程式碼、引用、
code fence 加 SQL/C# 關鍵字級高亮。在 BWK awk（macOS）、busybox awk、gawk 三種
實作下輸出**逐位元組相同**。

**MCP server 用 shell 講 JSON-RPC。** 產生 JSON 很容易（跳脫規則固定、UTF-8 原樣
通過）；難的是解析 —— 但真正需要的欄位路徑只有幾個，所以 `json_get.awk` 是個小
tokenizer，把一行 JSON 攤平成 `路徑<TAB>值`，包含 `\uXXXX` 還原（有些 client 會把
非 ASCII 全部逃逸，不還原的話中文全變成 `?`）。

全部加起來約 1,500 行。

## 取捨與副作用

這一節請讀完。有些是刻意的取捨，其中一項會弄丟資料。

### 待辦沒有持久化

它們活在 tmux server 的記憶體裡。**重開機或 `kill-server`，就沒了。**
關掉某則的 window 就等於刪掉那則 —— 沒有第二份。

內容重要的話請用 `scripts/backup.sh`。用 `tmux-resurrect` hook 做持久化是規劃中，
還沒做。

### N 則待辦就是 N 個 window

二十則待辦就是 window 列表裡二十個閒置的 window。這是「讓待辦和工作區成為同一個
物件」的代價。如果你會長期累積幾十則，這個設計會讓你不舒服。

### 清單開著的時候會接管按鍵

選單那個 window 會設 tmux 的 `key-table`，使它**跳過你整張 root key table**
（`bind -n ...` 那些）。沒有這一步，`C-d`、`C-p`、`C-t` 這類常見綁定會在按鍵
到達清單之前就被攔走。`prefix` 不受影響。

`key-table` 是 *session* 層級的選項，所以我們會存舊值、離開時還原，並掛 hook 讓你
切到別的 window 時也還回去。萬一選單以跳過收尾的方式被殺掉，
執行 `tmux set-option -u key-table` 即可。

### 開著時會安裝 session 層級的 hook

`client-resized`、`client-attached`、`client-detached`、`after-resize-pane`、
`after-select-window`、`window-pane-changed` —— 全都掛在 session 層級，離開時全部
移除。它們負責在 resize 後重畫，以及把焦點從預覽窗格彈回來（那個窗格不讀鍵，
焦點掉進去看起來就像整個介面當掉）。

### 派工是真的會跑 agent

`C-g` 會在那個 window 裡輸入 `claude` 並把待辦當 prompt 貼進去。**會花 token。**
而且 `claude` 必須在**那個窗格的互動 shell** 的 PATH 裡 —— 不是 tmux server 的 PATH。

### 範圍預設是每個 session 各自獨立

你只看得到 window 住在當前 session 的待辦。`Tab` 可切成全部；
`@agent_backlog_scope global` 改預設值。

### 沒做的

表格不 render（要算東亞字元寬度）。篩選是子字串比對，不是模糊比對。
JSON-RPC 的 batch 不支援。不跨機器 —— 範圍到單一 tmux server 為止。

## 從舊的 `@prompt` / `@status` 遷移

```tmux
set -g @agent_backlog_compat on
```

相容模式會連舊 key 一起讀，狀態也寫回該則原本用的那個 key —— 所以兩套看的是
同一份資料，不會分岔。

`scripts/migrate.sh` 會把舊 key 複製到新的命名空間（刻意保留舊的）。但複製之後
就是**兩份資料**，之後會各走各的；確定要永久搬家時才跑它。

## 移除

```sh
tmux unbind A
tmux kill-window -t '[backlog]' 2>/dev/null
for h in client-resized client-attached client-detached after-resize-pane \
         after-select-window window-pane-changed; do
    tmux set-hook -u "$h"
done
tmux set-option -u key-table
```

你的待辦本身是 window，要留要關自己決定。

## 文件

設計脈絡、研究結論，以及開發過程中踩到的一長串坑，都在 [docs/](docs/)。
實作細節看 [docs/07-implementation.md](docs/07-implementation.md)。

## 授權

MIT
