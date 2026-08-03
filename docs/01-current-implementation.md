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

## tmux（寫新版時新踩到的）

這一批是 2026-08-01 實作零依賴版本時撞出來的，見
[07-implementation.md](07-implementation.md)。

- **tmux 3.4 會把控制字元逃逸成字面的 `\037`**（六個字元），3.6a 則原樣輸出。用 ASCII
  unit separator 當 `-F` 的欄位分隔符，在 Alpine 上整排欄位會消失。**改用 tab** ——
  兩個版本都原樣通過。（上面「不要用 tab」那條是指預設 IFS/FS 會併連續欄位；
  awk 用明確分隔符 `split`、shell 用 `cut -d` 都不會併）
- **`trap` 一定要攔 `HUP`**。`kill-window` 送的就是 SIGHUP，只攔 `EXIT INT TERM` 的話
  收尾完全不會跑 —— 實際後果是 `/tmp/ab.*` 一直累積、hook 留著指向死掉的 pane
- **空字串的 `-t` 等於「當前的」**。`kill-window -t ""` 會殺掉使用者正在看的 window。
  凡是拿變數當 target，先確認它非空再下指令
- **`detach-client` 不會對其他 client 發 `client-resized`**。只掛這一個 hook 的話，
  小 client 離開後版面回不來。要一併掛 `client-attached` / `client-detached`
- **多個 client 附著時，window 尺寸由 `window-size` 決定**（預設 `latest`）。
  有一個異常小的 client 就會把版面壓垮
- **`resize-pane` 不會觸發 `client-resized`**，要用 `after-resize-pane`

## 鍵位：不要跟使用者的 config 搶

**選單那個 window 設 `key-table` 指到一張不存在的表，就等於整張 root table 被跳過**，
所有按鍵直接落到程式手上，`prefix` 不受影響：

```sh
tmux set-option -w -t "$MYWIN" key-table agent-backlog
```

沒有這行的話，使用者 `~/.tmux.conf` 裡任何 `bind -n` 都會先攔走。
實際在這台機器上遇到的：`C-d` 開分割、`C-p` 選 session、`C-t` 開新 window、
`C-s` 分割、`C-w` 殺 pane、`M-方向鍵` 切窗格。**挑鍵閃避沒有用** ——
下一台機器就是另一組 config。

其他相關的：

- **訊號的 `trap` 執行完會「繼續往下跑」，不會自己結束。** 只寫
  `trap cleanup HUP` 等於把「終端機關掉就結束」這個預設行為拆掉，
  然後主迴圈會對著已死的 tty 空轉。實測後果：**20 個孤兒行程、11% CPU、
  最久跑了 1 小時 48 分**。訊號的 handler 一定要自己 `exit`：

  ```sh
  trap cleanup EXIT
  trap 'cleanup; exit 130' INT TERM HUP QUIT
  ```

- **阻塞式讀取讀到空的 = tty 沒了**。要當結束條件處理，否則就是無窮迴圈。
  但也可能只是被訊號打斷（`SIGWINCH`），所以連續數次才認定
- **`key-table` 是 session 層級的選項**。`set -w` / `set -p` 都會被 tmux 悄悄轉成
  session，所以它**不會隨著你的 window 一起消失**。用完沒還原的話，整個 session
  從此跳過 root 表，使用者的 `C-p` `C-t` `C-d` 全部失效，而且完全看不出原因。
  一定要存舊值、離開時還原；另外掛 `after-select-window` hook，讓使用者切到
  別的 window 時 root 表也還回去
- **tmux 的鍵綁定區分大小寫**。`bind-key A` 之後按 `a` 完全沒反應，而且**不會有任何
  錯誤訊息** —— 看起來就像整個 plugin 壞掉。單一字母的鍵兩個大小寫都綁
- **`C-s` 是 XOFF**（軟體流量控制）。還沒進 raw 模式的那一層終端機會吃掉它並凍住輸出 ——
  測試時整個畫面停格，很容易誤判成程式當掉
- **`send-keys` 不經過鍵表**，是直接把位元組塞進 pane。所以「某個鍵會不會被攔」
  用 `send-keys` 測不出來，一定要用真的 attached client
- **`confirm-before` 需要明確的 target-client**。從 pane 裡呼叫會回 `no current client`。
  自己在畫面上問 y/n 反而單純

## 鍵位：搶不贏，別搶（歷史，已被上面的 key-table 取代）

- **macOS 吃掉 `Ctrl+←/→`**（系統的切換桌面空間），那些位元組根本不會到終端機
- **使用者的 `~/.tmux.conf` 可能用 root table 吃掉 `Option+←/→`**
  （`bind -n M-Left select-pane -L`）—— tmux 在轉發給程式之前就攔下來了
- 結論：**能交給 tmux 做的就交給它**，我們只掛 hook 對變化做反應。
  調整分隔線就用 tmux 原本的 `prefix + ⌥←→`，程式端靠 `after-resize-pane` 得知

## 行程判斷

- **`pane_current_command` 對 Claude Code 是版本字串**（實測 `2.1.220`），不是 `claude`。
  想知道「起來了沒」，比對「跟啟動前是不是不一樣」比比對特定名稱可靠
- **`run-shell` 繼承的是 tmux server 當初的 PATH**，不是那個 pane 的互動 shell 的
  （後者才會載入 profile）。所以在 `run-shell` 裡 `command -v claude` 找不到，
  不代表 pane 裡打 `claude` 會失敗

## 內容傳輸

- 派工要把 markdown 送進 TUI，用 **`load-buffer` ＋ `paste-buffer`**，
  不要 `send-keys` 拼字串也不要暫存檔轉手 —— buffer 完全不經過 shell，
  引號、反引號、換行都不會被解析壞掉

## `unset TMUX` 是拆安全鎖

從外部（例如 `limactl shell` 進 VM）attach 時需要清掉繼承來的 `$TMUX`，
但**同一支腳本如果在 session 內部被執行，就會變成自己 attach 自己** ——
client 的尺寸來自 pane，pane 又跟著 window 走，每次 resize 互相回饋，
高度一路掉到 1 列，畫面永遠在抖。

判斷「我現在在哪」再決定要不要清：

```sh
if [ -n "$TMUX" ] && tmux display -p '#{session_name}' 2>/dev/null | grep -qx backlog; then
    exec sh .../open.sh          # 已經在裡面 → 只重開選單
fi
unset TMUX TMUX_TMPDIR           # 從外面進來 → 才需要清
exec tmux attach -t backlog
```

## 終端機

- **raw 模式關掉 ONLCR**，`\n` 只換行不歸位，每行會從上一行結束的欄位開始印。
  要自己補 `\r`。awk 的 `ORS` 幫不上忙 —— 它只作用在 `print`，而 `print` 常常是拿來
  寫檔給 shell 讀的，補了 CR 反而污染資料
- **寫到最後一列的最後一格會讓終端機捲一行**，把最上面那行頂掉。
  寫之前關掉自動換行（`\033[?7l` … `\033[?7h`），超出的直接被丟掉 ——
  這也順便繞開了「算不出中文顯示寬度」的問題
- **框線／分隔線不要寫死長度**。畫不到右緣看起來像「畫到一半」，很刺眼。
  寬度要由呼叫端傳進來，並在 resize 後讓 render 快取失效
- **resize 是連續事件**（拖曳分隔線、連按 `⌥←→`、縮放終端機都會連發），
  每一步都重畫就是閃爍。收到訊號只記旗標，用短逾時讀把後續吸收完再畫一次
- **不要每次重畫都 `\033[2J`**，那是肉眼可見的閃爍。改成游標歸位 ＋ 逐行 `\033[K`，
  最後 `\033[J` 清掉殘留

## 測試環境

- 驗證 tmux 行為要用**隔離的 server**（`env -u TMUX TMUX_TMPDIR=$D tmux ...`），不要動到
  使用者真正的 item
- 但 inner shell **不能繼承 `TMUX_TMPDIR`**，否則 CLI 會去問那台空的測試 server
  （踩過：`show` 回空的，誤判成程式壞了）
- 要測互動 UI（`choose-tree` 等）需要 attached client。detached session 上跑
  `choose-tree` 不會有任何反應。做法：起兩個 server，driver 的 window 裡
  `attach` 到 subject，再從 driver `capture-pane`
- macOS 沒有 `timeout` / `gtimeout`
