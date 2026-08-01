# 03 — 純 tmux 可行性研究

## 問題

能不能做成**純 tmux plugin**，不靠 fzf / rich / nvim / node？

## 結論

**大部分功能 tmux 自己就有，而且比我們自寫的好。** 唯一真做不到的是 markdown render
與語法高亮 —— 而那個可以自己用 awk 寫（見 [02](02-research-markdown-renderers.md)）。

測試環境：tmux 3.6a。

## 逐項實測

| 功能 | 現在靠 | 純 tmux | 實測 |
|---|---|---|---|
| 儲存 | tmux window options | ✅ | 本來就是 |
| 只列出待辦 | node 過濾 | ✅ `choose-tree -f '#{!=:#{@action_items_prompt},}'` | 只列出 3 則，`不是待辦` 被排除 |
| 狀態欄＋標題 | node `formatRows` | ✅ `-F '#{@action_items_status}  #{window_name}'` | 顯示 `pending  item-1` |
| **即時 preview** | fzf ＋ rich | ✅ **choose-tree 內建** | 滿版顯示該 window 的 pane，CJK 寬度正確 |
| 增量搜尋 | fzf 模糊搜尋 | ⚠️ 只有 format 語法過濾，**不是**模糊搜尋 | |
| 刪除確認 | 自寫 `x` `x` 兩段 | ✅ `confirm-before -p` | 內建的比自寫的好 |
| 切過去 | node `focus` | ✅ choose-tree 按 Enter | |
| 派工 | node `dispatch` | ✅ `send-keys` | |
| 動作選單 | — | ✅ `display-menu` | |
| **markdown render** | rich / markview | ❌ tmux 沒有 markdown 概念 | 自製 awk 可補 |
| **語法高亮** | rich / treesitter | ❌ 同上 | 自製 awk 可補 |

## 關鍵設計轉換：把內容印進 pane

preview 之所以能純 tmux，是因為一個轉換：

> **把 render 過的內容印進 pane 本身。**
> `choose-tree` 的內建 preview 顯示的就是那個 window 的 pane 畫面。

內容既是資料也是畫面，不需要外部 renderer，也不需要「preview 指令」。
render 成本在 add 時付一次，**移動游標是零成本**。

（`@prompt` 仍要保留原始 markdown，因為 `dispatch` 要拿它當 prompt。pane 裡的是給人看的。）

## 實測畫面

```
(0) - 0:   home
(1) └─> + 1: pending  prod-report-slowquery

┌ 1 (sort: index) (filter: active) ──────────────────────────────────────────┐
│ 3. 優化方向擇一評估：                                                       │
│    - 加覆蓋索引 `(CurrencyCode, ReportYear, PlayerId)` include `PlayerWi…`  │
│    - 改成增量／預聚合表（本 repo 報表本來就走預處理路線）                    │
│ ## 期望產出                                                                 │
│ 是否需要優化的結論 + 具體方案（索引 or 預聚合）…                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

完全沒有用到 fzf。

## 兩個實測到的問題

### 1. preview 顯示的是 pane 的**當前畫面**，也就是內容的尾巴

上圖看到的是第 46 行附近的「## 期望產出」，不是標題。內容超過一個螢幕就只看得到結尾。

可能的解法（未驗證）：

- 限制印進 pane 的內容長度（例如只印前 N 行 ＋「按 Enter 看全文」）
- 把 pane 送進 copy-mode 並捲到頂（`send-keys -X history-top`），讓 preview 顯示開頭 ——
  **需要驗證 choose-tree 的 preview 是否會顯示 copy-mode 的檢視位置**
- 兩者結合：印摘要進 pane，全文靠按鍵開

### 2. 沒有模糊搜尋

`choose-tree` 有 `-f` 過濾，但那是 tmux format 語法（要打 `#{m:*foo*,#{window_name}}`
這種），不是 fzf 那種邊打邊縮小的模糊搜尋。

待辦數量在十幾則的量級時影響不大；上百則就會有感。

## 生態系檢查：沒有撞車

| 現有 plugin | 實際上是 |
|---|---|
| `chriszarate/tmux-tasks` | TaskWarrior 的 status bar 顯示 |
| `arkane-systems/tmux-taskman` | 開一個 htop/top pane，是行程監控 |
| `YlanAllouche/tmux-task-monitor` | 同上，資源監控 |
| `raine/workmux` | git worktree ＋ 一個 window，最接近，但主題是平行開發 |

**沒有人做「待辦 = window ＋ 可派給 AI agent 執行 ＋ 人能 attach 接手」。** 位置是空的。

## TPM plugin 的門檻很低

TPM 對 plugin 的定義：**一個 git repo ＋ 至少一個可執行的 `*.tmux` 檔**，裡面用
`tmux bind-key` / `set-option` 綁東西。TPM 安裝時把所有 `*.tmux` source 一遍就完事。
沒有 C API、沒有 ABI、沒有註冊流程。

參考起點：`tmux-plugins/tmux-sensible`（最簡單的真實 plugin）。

## 持久化：可以靠 tmux-resurrect 的 hook

tmux-resurrect 提供四個 hook：

| hook | 時機 |
|---|---|
| `@resurrect-hook-post-save-layout` | 存完所有 session/pane/window 之後，**拿得到 state 檔路徑** |
| `@resurrect-hook-post-save-all` | 存檔流程最後 |
| `@resurrect-hook-pre-restore-all` | 任何 tmux 狀態被更動之前 |
| `@resurrect-hook-pre-restore-pane-processes` | 還原行程之前 |

**resurrect 本身不會存 window user options**，但 hook 足夠我們自己 dump/restore。

### 可直接抄的前例：`timvw/tmux-assistant-resurrect`

它做的事跟我們高度重疊 —— 專門 resurrect Claude Code / OpenCode / Codex 的 session：

- post-save hook 把自己的 `assistant-sessions.json` 寫到 resurrect 目錄旁
- post-restore hook 讀回來，重建 CLI 指令並 `send-keys`（例如 `claude --resume <id>`）
- 依賴：tmux 3.x、TPM、`jq`
- **它的 `.tmux` 會自動往 `~/.claude/settings.json` 裝 hook**，`prefix+I` 一按就好

最後一點很重要：證明 **TPM plugin 在安裝時動 Claude 設定是有前例的**，
所以 `claude mcp add` 可以放進 `.tmux` 安裝流程，不必拆成兩個 repo。

## Node 依賴怎麼辦

TPM plugin 慣例是純 shell。三條路：

| 做法 | 代價 |
|---|---|
| 保留 Node，`.tmux` 檢查 `node` 與 `dist/` 存在，缺了給明確錯誤 | 最省事，對純 shell 使用者是門檻 |
| 人機介面改寫成 shell，Node 只留 MCP server | 最合慣例；但等於重寫，且 bash 的坑踩過（見 [01](01-current-implementation.md)） |
| 發 npm 套件，`.tmux` 只綁 key，實作靠 `npx` | 折衷，多一層網路依賴 |

若採「純 tmux 核心 ＋ 可選增強」策略（見 [04](04-roadmap.md)），第二條路的重寫範圍會小很多 ——
因為 `choose-tree` / `confirm-before` / `display-menu` 取代掉了大部分自寫的 UI 邏輯。

## 探測方法（重現用）

### 只列出待辦

```bash
tmux list-windows -a \
  -f '#{!=:#{@action_items_prompt},}' \
  -F '#{window_id} #{window_name} [#{@action_items_status}]'
```

### 互動式清單

```bash
# ⚠️ 不要用 run-shell —— 它會先展開 #{...}，filter 會變成 0/1 導致 no matches
tmux bind-key -n F5 choose-tree -Zw \
  -f '#{!=:#{@action_items_prompt},}' \
  -F '#{@action_items_status}  #{window_name}'
```

### 測互動 UI 需要 attached client

detached session 上跑 `choose-tree` **不會有任何反應**。做法：起兩個隔離 server，
driver 的 window 裡 `attach` 到 subject，再從 driver `capture-pane`：

```bash
DA=$(mktemp -d); DB=$(mktemp -d)
A() { env -u TMUX TMUX_TMPDIR=$DA tmux "$@"; }   # driver：從這裡 capture
B() { env -u TMUX TMUX_TMPDIR=$DB tmux "$@"; }   # subject：放待辦

B new-session -d -x 150 -y 34 -n home
# ... 建 window、設 option ...
B bind-key -n F5 choose-tree -Zw -f '...' -F '...'

A new-session -d -x 150 -y 34 -n drv
A send-keys -t drv "env -u TMUX TMUX_TMPDIR=$DB tmux attach -t 0" Enter
A send-keys -t drv F5
A capture-pane -pt drv
```
