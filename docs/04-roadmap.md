# 04 — 後續怎麼做

> **⚠️ 這份文件寫於實作之前，部分規劃已被實測推翻。**
> 階段一實際做出來的東西見 [07-implementation.md](07-implementation.md)。
> 最大的差異：`choose-tree` 被否決了（預覽不能捲、沒有模糊搜尋、resize 不重排），
> 改成自己寫選單迴圈、把 tmux 的 copy-mode 當捲動元件用。
> 階段二（持久化）與階段三（發佈）仍然有效。

## 策略：純 tmux 核心 ＋ 可選增強

```
核心（零依賴，POSIX shell + awk + tmux 內建）
  ├── 清單          choose-tree -f/-F
  ├── preview       choose-tree 內建（顯示 pane 畫面）
  ├── render        md.awk，在 add 時印進 pane
  ├── 刪除          confirm-before
  ├── 切過去        choose-tree Enter
  └── 派工 / 狀態   send-keys / set-option

可選增強（偵測得到才啟用，缺了功能不減）
  ├── nvim + markview    Ctrl-O 細讀（render 最完整）
  └── MCP server (Node)  給 agent 用的介面
```

理由：「零依賴／可發佈」與「內容好讀」兩個需求都成立。TPM plugin 慣例本來就允許
optional dependency，而已經寫好的 `view`（nvim）可以直接沿用。

---

## 階段一 —— 打地基（約 1 小時，含一個現存 bug 的修復）

### 1.1 tmux option 加 namespace ⚠️ 優先

```
@prompt   →  @action_items_prompt      （或 @agent_backlog_prompt，看專案定名）
@status   →  @action_items_status
```

**這不是為了發佈，是修現在就存在的 bug** —— 見
[01](01-current-implementation.md#1-tmux-option-沒有-namespace--最該優先修)。

要一併處理既有 item 的遷移（讀舊 key、寫新 key、刪舊 key），否則現有待辦會消失。

### 1.2 寫 `agent-backlog.tmux` 入口檔

把現在手寫在 `~/.tmux.conf` 第 44–49 行的 binding 搬進去。之後 `.tmux.conf` 只留
`set -g @plugin '...'`，而且已經是 TPM 相容格式 —— 用本機路徑就能測。

搬移時要一併處理（見
[01 的安裝狀態](01-current-implementation.md#目前這台機器的安裝狀態)）：

- **舊 binding 要明確 `unbind`** —— `source-file` 不會移除 config 裡已經沒有的 binding
- `Ctrl+/` 記得兩個都綁（`C-/` 與 `C-_`）
- 若專案改名，**MCP 註冊也要重下**：
  `claude mcp remove action-items && claude mcp add agent-backlog -- node .../dist/server.js`
- `~/.tmux.conf.bak` ~ `.bak4` 是改動過程留下的，確認新版可用後可刪

### 1.3 清單改用 `choose-tree`

```bash
tmux choose-tree -Zw \
  -f '#{!=:#{@agent_backlog_prompt},}' \
  -F '#{@agent_backlog_status}  #{window_name}'
```

刪除改用 `confirm-before`（取代自寫的 `x` `x` 兩段確認）。

### 1.4 `md.awk` 進 repo，add 時 render 進 pane

原型已可執行：[prototypes/md.awk](prototypes/md.awk)（155 行）。

`@prompt` 仍保留**原始 markdown**（`dispatch` 要拿它當 prompt），pane 裡的是給人看的
render 版本。

### 1.5 先解掉「preview 只看得到尾巴」

見 [03](03-research-pure-tmux.md#1-preview-顯示的是-pane-的當前畫面也就是內容的尾巴)。
**這是階段一唯一有未知數的項目**，建議先花 15 分鐘驗證 copy-mode `history-top` 的做法，
不成立就退回「只印摘要 ＋ 按鍵看全文」。

### 階段一完成後的狀態

- 你的 `.tmux.conf` 變乾淨
- 修掉一個真 bug
- 已經是 TPM 格式，隨時可以本機安裝測試
- preview 從 260ms 變成 0ms

---

## 階段二 —— 持久化

重開機／tmux server 掛掉，待辦全部消失。自己用勉強可接受，公開會是 issue 磁鐵。

做法：抄 `timvw/tmux-assistant-resurrect` 的模式（見
[03](03-research-pure-tmux.md#可直接抄的前例timvwtmux-assistant-resurrect)）：

- `@resurrect-hook-post-save-all` → dump 所有待辦的 window 名稱 / `@prompt` / `@status`
- `@resurrect-hook-pre-restore-all`（或 post-restore）→ 讀回來重建

**這是自己用也需要的功能，不是為了發佈。**

需要決定：dump 格式要不要相依 `jq`（resurrect 生態常見）還是自己用分隔符（避免多一個依賴）。

---

## 階段三 —— 才決定要不要公開

到這一步再處理：

- Node / MCP 怎麼包（三條路見 [03](03-research-pure-tmux.md#node-依賴怎麼辦)）
- `claude mcp add` 放進 `.tmux` 安裝流程（有前例）
- **「20 則待辦 = 20 個 window」怎麼向別人解釋** —— 這是很有主張的設計，要嘛給隱藏／
  摺疊的答案，要嘛明講是刻意取捨
- README、demo

---

## 待決策事項

| # | 問題 | 說明 |
|---|---|---|
| 1 | 專案定名與 option prefix | 目錄叫 `agent-backlog`，舊實作叫 `action-items`。option prefix 要用哪個？一旦寫進使用者的 tmux 就不好改 |
| 2 | `action-items` 要不要保留 | 是要原地改造、還是在 `agent-backlog` 重寫並廢棄舊的？ |
| 3 | 表格支援 | awk 對齊 CJK 表格要用 UTF-8 lead byte 的啟發式硬幹。要做嗎，還是表格就不 render？ |
| 4 | 模糊搜尋 | `choose-tree` 只有 format 過濾。待辦上百則才會有感 —— 現在不做？ |
| 5 | shell 重寫範圍 | 人機介面全改 shell（最合 TPM 慣例）還是保留 Node？ |

---

## 明確不做

- **長期保存** —— 待辦本質是短期的，長期追蹤請用 Jira
- **跨機器同步** —— 範圍就是同一台機器的同一個 tmux server
- **agent 自動刪除** —— 刪除是人的動作，MCP 刻意不提供 `delete`
- **glow** —— CJK 寬度壞掉且無解，見 [02](02-research-markdown-renderers.md#glow-212--cjk-寬度是壞的)

---

## 從 `action-items` 搬過來時務必帶走的

[01 的「實作上踩過的坑」](01-current-implementation.md#實作上踩過的坑)整段 —— 那些是
花時間換來的：`window_id` vs 名稱、`run-shell` 會展開 format、`display-popup -E` 會閃退、
tab 分隔符、CJK 標點吃掉變數名、markview 的 `buftype=nofile`、GNU 詞界在 macOS 失效。
