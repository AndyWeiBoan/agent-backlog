# 05 — 開發過程怎麼測試

## 現況：零測試

`action-items` 沒有任何測試，`package.json` 只有 `build` / `watch` / `start`。
研究階段全靠手動搭環境 —— 而且過程中**約有一半的失敗是測試腳本本身寫錯**，不是程式錯。
所以下面的坑要當成正式規格看待。

## 四層策略

| 層 | 對象 | 成本 | 該有多少 |
|---|---|---|---|
| 1 | `md.awk` render | 毫秒 | 最多 |
| 2 | tmux 操作 | 秒 | 中等 |
| 3 | 互動 UI | 十秒級、脆 | 只留關鍵路徑 |
| 4 | MCP server | 秒 | 每個 tool 一個 |

---

## 第 1 層：`md.awk` —— 純 stdin→stdout

沒有 tmux、沒有狀態。golden file 就夠：

```
tests/render/
  headings.md          headings.expected
  sql-fence.md         sql-fence.expected
  cjk-inline-code.md   cjk-inline-code.expected
  no-lexer-log.md      no-lexer-log.expected     # 沒有 lexer 的語言要原樣輸出
```

比對時**保留 ANSI** —— 顏色本身就是要驗的東西。

### ⚠️ 一定要跨 awk 實作測

已經踩過一次：GNU 的詞界 `\<` `\>` 在 macOS 內建的 BWK awk（`awk version 20200816`）
上**靜默失效** —— 不報錯，只是關鍵字完全沒上色。

本機只有 BWK awk（沒裝 gawk），但有 docker，三種都能跑：

```bash
awk -f md.awk in.md                                    # macOS BWK awk
docker run --rm -i busybox awk -f - < ...              # busybox awk
docker run --rm -i alpine sh -c 'apk add -q gawk && gawk -f ...'   # gawk
```

三者輸出必須一致。這是 CI 的最低門檻。

---

## 第 2 層：tmux 操作 —— 隔離 server

不要對使用者真正的 tmux server 做測試，會建立/刪除真的待辦。

```bash
D=$(mktemp -d /tmp/ab-test.XXXXXX)
T() { env -u TMUX TMUX_TMPDIR=$D tmux "$@"; }

T new-session -d -n home
# ... 操作 ...
T list-windows -a -F '#{window_name}|#{@agent_backlog_status}'   # 直接查 tmux 當斷言
T kill-server; rm -rf "$D"
```

### ⚠️ inner shell 不能繼承 `TMUX_TMPDIR`

在測試 window 裡跑 CLI 時要先 `unset TMUX_TMPDIR TMUX`，否則 CLI 會去問那台空的測試
server。踩過：`show` 回空的，一度誤判成程式壞了。

```bash
T send-keys -t t "unset TMUX_TMPDIR TMUX; node dist/cli.js view foo" Enter
```

---

## 第 3 層：互動 UI —— driver / subject 兩台 server

`choose-tree` / `fzf` / `nvim` 都需要 **attached client**。
**detached session 上跑 `choose-tree` 完全沒有反應**（踩過，一度以為指令壞了）。

```bash
DA=$(mktemp -d); DB=$(mktemp -d)
A() { env -u TMUX TMUX_TMPDIR=$DA tmux "$@"; }   # driver：從這裡 capture
B() { env -u TMUX TMUX_TMPDIR=$DB tmux "$@"; }   # subject：放待辦

B new-session -d -x 150 -y 34 -n home
B bind-key -n F5 choose-tree -Zw -f '...' -F '...'

A new-session -d -x 150 -y 34 -n drv
A send-keys -t drv "env -u TMUX TMUX_TMPDIR=$DB tmux attach -t 0" Enter
A send-keys -t drv F5
A capture-pane -pt drv      # -pe 保留顏色
```

### ⚠️ 不要用 `run-shell` 送含 format 的指令

`run-shell` 會**先展開 `#{...}`**。探測 `choose-tree -f '#{!=:#{@prompt},}'` 時中招：
filter 被求值成 `0`/`1`，出現 `filter: no matches`，`window_name` 也全變成當前 window 的值。

要傳原始 format 字串請用 `bind-key`（存的是原始字串），再送按鍵觸發。

---

## 第 4 層：MCP —— stdio JSON-RPC，不需要 Claude Code

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{...}}' \
  | env -u TMUX -u TMUX_PANE TMUX_TMPDIR=$D node dist/server.js
```

### ⚠️ 必須逐則送、等回應再送下一則

一次 pipe 全部訊息會**併發執行**。實測：`add` 和 `list` 一起送，`list` 先跑完回空的
（回應順序 id=3 在 id=2 前面就是證據）。那不是 server 的 bug，是測試錯。

bash 的 fifo 做法會卡住（試過，逾時）。建議寫個小 Node driver：
spawn server → 寫一則 → 等對應 id 的回應 → 寫下一則。

### ⚠️ 測試前要 `-u TMUX_PANE`

server 啟動時會呼叫 `rememberMain()`，它讀 `TMUX_PANE` 反查 window 並寫進 global option。
不清掉會污染到真正的 tmux server。

---

## 通用注意事項

- **macOS 沒有 `timeout` / `gtimeout`**。等待一律用：

  ```bash
  n=0; until <條件> || [ $n -ge 30 ]; do sleep 1; n=$((n+1)); done
  ```

- **`pkill -f` 要夠精確。** 踩過：`pkill -f "action-items/dist/server.js"` 把 Claude Code
  正在用的 MCP server 一起殺了。測試起的 process 要記 PID 個別 kill，或用專屬的
  `TMUX_TMPDIR` 路徑當 pattern。

- **顯示寬度斷言**要用 East Asian Width，不能用 `length()`。這支收進 `tests/lib/width.py`：

  ```python
  import sys, re, unicodedata
  for l in sys.stdin:
      p = re.sub(r'\x1b\[[0-9;]*m', '', l.rstrip('\n'))
      w = sum(2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in p)
      print(f'{w}\t{p}')
  ```

- **`cat -v` 會把 UTF-8 顯示成亂碼** —— 那是 `cat -v` 的問題，不是輸出壞了（誤判過一次）。
  要看 raw ANSI 用 `sed -n l` 或上面那支 python。

- **每個測試都要自己清乾淨**：`kill-server` ＋ `rm -rf $D`。測試用的 `TMUX_TMPDIR`
  統一放 `/tmp/ab-test.XXXXXX`，方便一次掃掉殘留。

---

## 什麼時候建

| 層 | 時機 |
|---|---|
| 1（`md.awk`） | **進 repo 的同時**（階段一 1.4）。便宜、跨平台風險最高、純函數 |
| 2、4 | 階段一結束後 |
| 3 | 介面穩定後。太早建，改一次 UI 就要重錄 |
