# 01 — 現況實作（`~/3rd-party/action-items`）

能跑的版本。Node + TypeScript，一份核心 `src/tmux.ts` 同時給 CLI 與 MCP server 用。

## 架構

```
src/tmux.ts     核心：所有 tmux 操作，資料模型定義
src/cli.ts      人的介面（fzf 清單、nvim 檢視、preview）
src/server.ts   MCP server（agent 的介面），stdio transport
```

兩個入口共用同一份 `tmux.ts`，所以人和 agent 看到的一定是同一份資料。

## 資料模型

| 存在哪 | 內容 |
|---|---|
| window 名稱 | 標題 |
| `@prompt` | 完整內容（派工時直接當 prompt） |
| `@status` | pending / running / blocked / done（任意字串，排版自動對齊） |
| `@action_items_main` (global) | main window 的 `window_id`，用於「回到 main」 |

「是不是 action item」的判斷 = **有沒有 `@prompt`**。

## MCP tools

| tool | 用途 |
|---|---|
| `list` | id / 狀態 / 標題 / 位置 / 該 window 目前跑什麼 |
| `add` | 建立 detached window 並存內容，**不啟動 claude** |
| `show` | 讀完整內容 |
| `dispatch` | 在該 window 啟動獨立 claude 實例並送出內容，狀態轉 running |
| `peek` | capture 該 window 畫面，看派出去的進度 |
| `set_status` | 更新狀態 |

**刻意沒有 `delete`** —— 刪除是人的動作，agent 不代勞。

## CLI

```
action-items pick                 # fzf 清單 ＋ 右側即時 preview（render 過的）
action-items list
action-items view <目標>          # nvim 唯讀檢視（markview 完整 render）
action-items preview <目標>       # render 成帶 ANSI 的 stdout（fzf preview 用）
action-items show <目標>          # 純文字，給 agent 用
action-items add <標題>           # 內容從 stdin
action-items dispatch <目標>
action-items status <目標> <值>
action-items main / set-main / focus / remove / confirm-delete / rows / peek
```

目標可用標題或 `window_id`（`@數字`）。

## 快捷鍵

```tmux
# ~/.tmux.conf 第 44–49 行
# action-items：Ctrl+/ 開清單（不需 prefix）。
# 綁兩種寫法：extended-keys 關閉時，終端機的 Ctrl+/ 實際送出 0x1F，tmux 認作 C-_。
bind -n C-/ display-popup -E -w 100% -h 100% 'node ~/3rd-party/action-items/dist/cli.js pick'
bind -n C-_ display-popup -E -w 100% -h 100% 'node ~/3rd-party/action-items/dist/cli.js pick'

bind P      display-popup -E -w 100% -h 100% 'node ~/3rd-party/action-items/dist/cli.js pick'
```

清單裡：`Enter` 切過去 · `Ctrl-O` nvim 細讀 · `Ctrl-G` 派工 · `x` `x` 刪除 · `Ctrl-R` 重整

nvim 檢視裡：`q` 關閉 · `w` 切換折行

### 為什麼要綁 `C-/` 和 `C-_` 兩個

終端機在 extended-keys（CSI u）關閉時，`Ctrl+/` 送出的是 `0x1F`（ASCII unit separator），
而 tmux 把 `0x1F` 顯示成 `C-_`。所以只綁 `C-/` 在多數終端機上按了不會有反應。
兩個都綁，開不開 extended-keys 都能用。

---

# 目前這台機器的安裝狀態

**不需要每次 source —— 設定已寫進 `~/.tmux.conf`，重開機也在。**
`source-file` 只是為了讓改動當下生效、不用重開 tmux。

| 項目 | 狀態 | 怎麼確認 |
|---|---|---|
| tmux binding | 已寫入 `~/.tmux.conf` 第 44–49 行 | `grep -n 'action-items' ~/.tmux.conf` |
| tmux binding（執行中的 server） | 已生效，與檔案一致 | `tmux list-keys -T root \| grep action` |
| MCP server | 已註冊，✔ Connected | `claude mcp list \| grep action-items` |
| Claude Code keybinding | **未改動**，`ctrl+l` 維持 `chat:clearInput` | `~/.claude/keybindings.json` |
| `~/.tmux.conf` 備份 | `.bak` / `.bak2` / `.bak3` / `.bak4` | 改動過程留下的，可刪 |

## 從零重建（換機器時照這個做）

```bash
# 1. 建置
cd ~/3rd-party/action-items && npm install && npm run build

# 2. 註冊 MCP（user scope，所有專案都看得到）
claude mcp add action-items -- node ~/3rd-party/action-items/dist/server.js

# 3. tmux 快捷鍵：把上面那段貼進 ~/.tmux.conf，然後
tmux source-file ~/.tmux.conf
```

### 可選增強（沒有也能跑）

| 工具 | 用途 | 沒有的話 |
|---|---|---|
| `fzf` | 清單 ＋ 即時 preview | `pick` 不能用，退回 `prefix w` |
| `uvx`（或 `rich`） | preview 的 markdown render | 自動降級：`glow` → 純文字 |
| `nvim` ＋ markview | `Ctrl-O` 細讀 | 少一個功能，其餘不受影響 |

---

# ⚠️ 已知 bug（未修）

## 1. tmux option 沒有 namespace —— 最該優先修

```
@prompt              ← 太通用
@status              ← 太通用
@action_items_main   ← 這個是對的
```

兩個方向都會出事：

- 別的 plugin 用同名 window option → 被我們覆寫
- **反過來更糟**：`list` 的判斷是「有 `@prompt` 就是 action item」，所以任何別的東西
  設了 `@prompt`，那個 window 就會出現在待辦清單裡

**這是現在就存在的 bug，跟要不要做成 plugin 無關。** 應改為
`@action_items_prompt` / `@action_items_status`。

## 2. 重開機 / tmux server 掛掉，所有 item 消失

item 活在 tmux server 記憶體。自己用勉強可接受，公開發佈會是 issue 磁鐵。
解法見 [04-roadmap.md](04-roadmap.md) 階段二。

## 3. preview 有延遲

每次移動游標約 **260ms**（node 啟動 ＋ 兩次 tmux 查詢 ＋ uvx 起 Python）。
11 則捲起來還行，但明顯感覺得到。詳見 [02](02-research-markdown-renderers.md)。

---

# 實作上踩過的坑

這些是花時間換來的，改寫時不要重蹈。

## tmux

- **目標一律用 `window_id`。** `tmux -t <名稱>` 只在**當前 session** 解析，跨 session 會
  `no such window`（實際踩過：在別的 session 按快捷鍵就爆了）
- **`run-shell` 會先展開 `#{...}`**。把含 format 的指令丟給 `run-shell` 會被提前求值 ——
  探測 `choose-tree -f '#{...}'` 時就中招，filter 變成 `0`/`1`，出現 `filter: no matches`。
  要傳原始 format 字串請用 `bind-key`（存的是原始字串）
- **`tmux source-file` 不會移除舊的 binding**。它只是「再執行一次 config」，config 裡沒有
  的 binding 不會被清掉。把 `C-l` 改成 `Ctrl-/` 時就中招 —— source 完舊的 `C-l` 還在。
  換鍵要明確：

  ```bash
  tmux unbind -n C-l    # root table
  tmux unbind C-l       # prefix table
  ```

- **`Ctrl+/` 要綁兩個鍵**。extended-keys 關閉時終端機送出的是 `0x1F`，tmux 認作 `C-_`，
  只綁 `C-/` 多數終端機按了沒反應
- **`display-popup -E` 在指令結束時就關閉**。空清單直接 `return`、或錯誤直接 exit，
  使用者只看到畫面閃一下。必須停住等按鍵
- **欄位分隔符不能用 tab**。tab 屬於 IFS whitespace，連續 tab 會被 `read`／awk 併成一個，
  空欄位消失導致整排跑位。改用 ASCII unit separator（``）
- **內容用暫存檔傳給 `send-keys`**，不要拼進命令列 —— 含引號、反引號、換行會被 shell 解析壞掉
  （這是 `dispatch` 唯一需要暫存檔的理由；preview / view 都不需要）

## bash（早期原型階段）

- **CJK 標點會被吸進變數名**：`$name（` → `unbound variable`。凡是變數後面接非 ASCII
  一律寫 `${name}`
- **`${1:?訊息...}` 裡含 `}`** 會截斷展開，導致 `case` 比對失敗

## fzf

- **要明確 `--height=100%`**，否則在 tmux popup 裡只佔一部分高度
- `display-menu` 做不到 live preview，要邊移動邊預覽只能用 chooser

## nvim（`view` 指令）

- **不能設 `buftype=nofile`** —— markview 預設 `ignore_buftypes = { "nofile" }`，設了就
  完全不 render（標題留著裸的 `##`）。唯讀改用 `-R` ＋ `nomodifiable`
- **filetype 必須用 `vim.schedule` 延後一個 tick 再設**。直接 `-c 'set ft=markdown'` 時
  lazy.nvim 還沒把 markview attach 上去，只有 code fence 被 conceal，標題不 render
- 使用者的 config 對 markdown 設 `wrap=false`（markview 在 wrap 開啟時無法 render
  超出視窗寬度的表格）。viewer 覆寫成 `wrap` 並綁 `w` 切換

## 測試環境

- 驗證 tmux 行為要用**隔離的 server**（`env -u TMUX TMUX_TMPDIR=$D tmux ...`），不要動到
  使用者真正的 item
- 但 inner shell **不能繼承 `TMUX_TMPDIR`**，否則 CLI 會去問那台空的測試 server
  （踩過：`show` 回空的，誤判成程式壞了）
- 要測互動 UI（`choose-tree` 等）需要 attached client。detached session 上跑
  `choose-tree` 不會有任何反應。做法：起兩個 server，driver 的 window 裡
  `attach` 到 subject，再從 driver `capture-pane`
- macOS 沒有 `timeout` / `gtimeout`
