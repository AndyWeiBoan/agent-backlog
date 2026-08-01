# 06 — 開發失敗怎麼回到現在這個能用的狀態

## 最大風險：現在的實作不在版本控制裡

```
~/3rd-party/action-items   → fatal: not a git repository
~/3rd-party/agent-backlog  → fatal: not a git repository
```

**目前能跑的版本只存在硬碟上這一份，沒有任何歷史。** 改壞了就沒得回。

## 動工前第一件事（在寫任何 code 之前做）

```bash
cd ~/3rd-party/action-items
git init
printf 'node_modules/\n' > .gitignore
git add -A                      # 注意：dist/ 要進版控，見下方說明
git commit -m "chore|封存目前可運作的版本（研究階段結束）"
git tag working-baseline
```

`dist/` **要進版控**，不要 gitignore —— 回滾時希望 `git checkout` 完就能直接跑，
不需要先 `npm install && npm run build`（那會受 npm registry 與 node 版本影響）。

同樣對 `agent-backlog` 也做一次。

---

## 現在這個「能用的狀態」由四塊組成

回滾要四塊都對得上，缺一塊就不會動。

| # | 東西 | 位置 | 怎麼確認 |
|---|---|---|---|
| 1 | 程式 ＋ 建置產物 | `~/3rd-party/action-items/{src,dist}` | `node dist/cli.js list` |
| 2 | tmux 快捷鍵 | `~/.tmux.conf` 第 44–49 行 | `tmux list-keys -T root \| grep action` |
| 3 | MCP 註冊 | `~/.claude.json` 的 `"action-items"` | `claude mcp list \| grep action-items` |
| 4 | 待辦資料 | tmux server 記憶體（window options） | `tmux list-windows -a -F '#{window_name} #{@prompt}'` |

第 4 塊**沒有備份機制**（見 [04](04-roadmap.md) 階段二）。開發期間如果 kill 到 tmux
server，現有待辦就沒了 —— 動工前先手動 dump 一份：

```bash
tmux list-windows -a -F '#{window_id}#{window_name}#{@status}#{@prompt}' \
  > ~/action-items-backup-$(date +%Y%m%d).txt
```

（分隔符是 ASCII unit separator `\x1f`，因為內容含換行與各種標點。）

---

## 完整還原步驟

```bash
# 1. 程式
cd ~/3rd-party/action-items
git checkout working-baseline

# 2. tmux 快捷鍵（如果被新版蓋掉了）
tmux unbind -n C-/ ; tmux unbind -n C-_ ; tmux unbind P     # 先清新版綁的
# 把下面這段確認在 ~/.tmux.conf 裡，然後 source
tmux source-file ~/.tmux.conf

# 3. MCP
claude mcp remove agent-backlog 2>/dev/null
claude mcp add action-items -- node ~/3rd-party/action-items/dist/server.js
# 之後在 Claude Code 用 /mcp 重連，或重開
```

`~/.tmux.conf` 該有的那段：

```tmux
# action-items：Ctrl+/ 開清單（不需 prefix）。
# 綁兩種寫法：extended-keys 關閉時，終端機的 Ctrl+/ 實際送出 0x1F，tmux 認作 C-_。
bind -n C-/ display-popup -E -w 100% -h 100% 'node ~/3rd-party/action-items/dist/cli.js pick'
bind -n C-_ display-popup -E -w 100% -h 100% 'node ~/3rd-party/action-items/dist/cli.js pick'

bind P display-popup -E -w 100% -h 100% 'node ~/3rd-party/action-items/dist/cli.js pick'
```

> **`tmux source-file` 不會移除舊 binding** —— 它只是再執行一次 config，config 裡沒有的
> binding 不會被清掉。所以上面要先明確 `unbind`。

還有 `~/.tmux.conf.bak` ~ `.bak4` 四份備份可用，但那是研究過程隨手留的，
**不保證對應到哪個可運作狀態** —— 以 git tag 為準，備份檔確認新版可用後就刪掉。

---

## 更好的做法：不要做破壞性遷移，讓兩套並存

上面是「壞了再修」。更安全的是一開始就讓新舊並行，回滾只是「不再按那個鍵」。

三件事分開就不會衝突：

| | 舊（action-items） | 新（agent-backlog） |
|---|---|---|
| 目錄 | `~/3rd-party/action-items` | `~/3rd-party/agent-backlog` |
| option prefix | `@prompt` / `@status` | `@agent_backlog_prompt` / `@agent_backlog_status` |
| 快捷鍵 | `C-/` `C-_` `prefix P` | `prefix A`（或別的沒用到的） |
| MCP 名稱 | `action-items` | `agent-backlog` |

**option prefix 不同是關鍵** —— 新版的 `-f` filter 只會看到自己建的待辦，舊版只看到舊的，
互不干擾。同一個 tmux server 上兩套可以同時活著。

> **不是開兩台 tmux server。** 日常使用永遠只有一台，新舊兩套跑在同一台上，
> 靠 option prefix 區隔資料、靠不同快捷鍵區隔入口 —— `C-/` 開舊的、`prefix A` 開新的，
> 兩個都能按，**不需要切換**。
>
> 多台 server 只出現在[測試](05-testing.md)（用 `TMUX_TMPDIR` 隔離，避免動到真正的待辦），
> 跟日常使用無關。

新版穩定之後再做一次性遷移（讀舊 key、寫新 key、刪舊 key），然後把舊的整包刪掉。

> ⚠️ 這也是為什麼 [04](04-roadmap.md) 把「專案定名與 option prefix」列為第一個要決定的事：
> prefix 一旦寫進使用者的 tmux 就不好改。

---

## 各階段的回滾點與觸發條件

| 階段 | 回滾成本 | 什麼情況該回滾 |
|---|---|---|
| 一：namespace ＋ `.tmux` ＋ `choose-tree` ＋ `md.awk` | 低（並存策略下只是不按新鍵） | `choose-tree` 的 preview 只看得到內容尾巴且三種解法都不成立 |
| 二：持久化 | 中（會動 resurrect hook） | dump/restore 會弄壞既有 resurrect 流程 |
| 三：發佈 | 高（別人裝了） | — 發佈前必須先有第 1、2、4 層測試 |

階段一唯一有未知數的是 preview 位置問題（見
[03](03-research-pure-tmux.md#1-preview-顯示的是-pane-的當前畫面也就是內容的尾巴)）。
**建議先花 15 分鐘驗證那一項再動工** —— 它決定純 tmux 路線成不成立，早點知道比較好回頭。

---

## 開發期間的自保習慣

- **不要對真正的 tmux server 跑測試**（見 [05](05-testing.md)）
- **`pkill -f` 要精確** —— 踩過：`pkill -f "action-items/dist/server.js"` 把 Claude Code
  正在用的 MCP server 一起殺了
- 動 `~/.tmux.conf` 前先 `cp` 一份帶日期的，改完在**新開的**測試 session 驗，
  不要只在當前 session 驗（當前 session 可能有殘留的舊 binding 造成假象）
- 每完成一小塊就 commit，不要累積一大包
