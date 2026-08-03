# agent-backlog

人與 AI agent 共享的待辦清單，長在 tmux 裡。

**一則待辦 = 一個 tmux window。** 沒有資料庫、沒有 JSON 檔 —— 清單就是 window 列表。
所以「待辦」與「執行它的地方」是同一個物件，不會有兩份狀態要同步；
你可以直接切進去接手，agent 也能在那裡跑。

零依賴：`tmux` `sh` `awk` `sed` `stty` `dd` `od` `cut` `mkfifo` `mktemp`，全部 POSIX。
沒有 node、python、fzf、jq。

```
❯ kyc                                    │ █ Prod: KYC 縮圖遺失
  2/11 則                                │
                                         │ ┃ 現象
 pending  prod-kyc-thumbnail-missing     │ ● 環境：prod，7d 82 筆
 blocked  prod-kyc-review-queue-stuck    │ ● 影響：審核頁開不了圖
                                         │
                                         │ ┌─ sql ─────
                                         │ │ SELECT ...
 ↑↓ 選擇  C-e/C-y 捲預覽  Enter 切過去   │
```

## 需求

- **macOS 或 Linux**（其他平台會在載入時擋下來）
- **tmux 3.0 以上**（實測過 3.4 與 3.6a）

## 安裝

### TPM

```tmux
set -g @plugin 'your-name/agent-backlog'      # 發佈到 GitHub 之後
run '~/.tmux/plugins/tpm/tpm'
```

然後 `prefix + I`。

**還沒發佈的話，`@plugin` 直接給本機 repo 的絕對路徑就好** ——
TPM 會先試著直接 `git clone "$plugin"`，失敗才退回去展開成 GitHub 網址：

```tmux
set -g @plugin '/home/you/src/agent-backlog'
```

> - **路徑不能用 `$HOME` 或 `~`** —— tmux 不會展開 option 值裡的變數
> - **TPM 自己需要 `bash` 與 `git`**（它的腳本是 bash 寫的）。
>   這是 TPM 的依賴，不是本 plugin 的 —— 用「手動」那條路就完全不需要
> - `prefix + I` 會「下載 ＋ 載入」兩件事一起做。
>   若是用 `~/.tmux/plugins/tpm/bin/install_plugins` 手動裝，它只下載，
>   要再 `tmux source-file ~/.tmux.conf` 才會生效

在 Alpine（tmux 3.4 / busybox）上實測過整條流程：clone → 載入 → `prefix + a`
開起來的確實是 `~/.tmux/plugins/agent-backlog/` 底下那一份。

### 手動

```tmux
run-shell ~/3rd-party/agent-backlog/agent-backlog.tmux
```

放在 `~/.tmux.conf` 裡，然後 `tmux source-file ~/.tmux.conf`。

> `source-file` **不會移除**設定檔裡已經沒有的舊 binding。換鍵的話要自己
> `tmux unbind <舊鍵>`。

## 用法

`prefix + A` 開清單（大小寫都綁了 —— tmux 的鍵區分大小寫，只綁一個的話按錯就完全沒反應，也沒有錯誤訊息）。

| 鍵 | 動作 |
|---|---|
| 打字 | 篩選（子字串比對，中文可用） |
| `↑` `↓` | 選擇（`C-p` / `C-n` 同） |
| `C-e` `C-y` | 預覽捲一行 |
| `C-d` `C-u` | 預覽捲半頁 |
| `C-f` `C-b` | 預覽捲整頁 |
| `prefix` + `⌥←` `⌥→` | 調整中間分隔線（tmux 原生，寬度會記住） |
| `Enter` | 切到該待辦 |
| `C-g` | 派工：在該 window 啟動 claude 並把內容送進去 |
| `C-t` | 輪替狀態（pending → blocked → done） |
| `C-x` | 刪除（會先問 y/n） |
| `Tab` | 切換「本 session／全部」 |
| `C-r` | 重新讀取清單 |
| `ESC` `C-c` | 離開，回到開清單之前的 window |

清單開著的時候，**這個 window 會跳過你 `~/.tmux.conf` 的 root key table**
（`bind -n` 那些），否則像 `C-d` `C-p` `C-t` 這種常見綁定會在按鍵到達清單之前被攔走。
`prefix` 不受影響。

新增一則：

```sh
echo '## 現象
prod 上 KYC 縮圖開不出來，7d 82 筆。' | sh scripts/add.sh prod-kyc-thumbnail-missing
```

## 設定

| option | 預設 | 說明 |
|---|---|---|
| `@agent_backlog_key` | `A` | 開清單的鍵（在 prefix 之後） |
| `@agent_backlog_root_key` | — | 不需要 prefix 的鍵，空白分隔可給多個 |
| `@agent_backlog_no_key` | — | 設 `on` 就完全不綁鍵，自己綁 |
| `@agent_backlog_compat` | — | 設 `on` 就連舊版的 `@prompt` / `@status` 一起認 |
| `@agent_backlog_scope` | `session` | `session` 只看本 session、`global` 看全部 |

想用 `Ctrl+/` 這種不需要 prefix 的鍵：

```tmux
set -g @agent_backlog_root_key 'C-/ C-_'
```

> **`Ctrl+/` 一定要綁兩個。** extended-keys（CSI u）關閉時，終端機送出的
> 其實是 `0x1F`，tmux 認作 `C-_`。只綁 `C-/` 在多數終端機按了不會有反應。

自己綁的話，路徑可以從 `@agent_backlog_path` 拿，**並且要把 `#{session_id}` 帶上**
（`run-shell` 會在按鍵當下展開它；少了它，選單可能開到別的 session 去）：

```tmux
set -g @agent_backlog_no_key on
bind-key -n C-o run-shell "sh #{@agent_backlog_path}/scripts/open.sh '#{session_id}'"
```

## 給 agent 用（MCP）

```sh
claude mcp add agent-backlog -- sh ~/3rd-party/agent-backlog/scripts/mcp-server.sh
```

**MCP server 也是零依賴的**（POSIX sh ＋ awk），不需要 node。
工具：`list` `show` `add` `dispatch` `peek` `set_status`。
刻意沒有 `delete` —— 刪除是人的動作，agent 不代勞。

註冊的理由跟功能無關：同樣的事用 shell script 就做得到，但新的 Claude Code
session 不會知道那些 script 存在。**買的是可發現性。**

> MCP server 連的是「環境變數指到的那台 tmux」。`$TMUX` 會蓋過 `$TMUX_TMPDIR`，
> 所以從 tmux 裡啟動的 client，它的 MCP server 連的就是同一台 —— 這通常正是你要的。

## 新舊並行與切換

舊版 action-items 用沒有 namespace 的 `@prompt` / `@status`，新版用
`@agent_backlog_prompt` / `@agent_backlog_status`。兩套可以同時活在
同一個 tmux server 上 —— 不同的鍵、不同的 MCP 名稱、不同的 option key。

**建議：先開相容模式試用，不要急著遷移。**

```tmux
set -g @agent_backlog_compat on
```

相容模式下新版**連舊 key 也一起讀**，狀態改動也寫回原本那個 key。
所以兩套看的是同一份資料，不會分岔；「切換」就只是換一個鍵按。

| 做法 | 新版看得到舊資料 | 會不會分岔 | 什麼時候用 |
|---|---|---|---|
| 什麼都不做 | ❌ | — | 只想看新 UI 長怎樣 |
| `@agent_backlog_compat on` | ✅ | ❌ 同一份 | **試用期（推薦）** |
| `sh scripts/migrate.sh` | ✅ | ⚠️ 兩份 | 決定要換過去了 |

`migrate.sh` 會把舊 key 複製一份到新 key，**刻意不刪舊的**。
但複製之後就是兩份資料了 —— 兩邊各改各的不會同步。
所以它是「確定要搬家」時才跑的，跑完接著把舊的整套停掉。

完全換過去之後清掉舊 key：

```sh
tmux list-windows -a -f '#{!=:#{@prompt},}' -F '#{window_id}' | while read -r w; do
    tmux set-option -wu -t "$w" @prompt
    tmux set-option -wu -t "$w" @status
done
```

回滾永遠只是「不按那個鍵」—— 把 `.tmux.conf` 裡的 `run-shell` 那行拿掉，
或 `tmux unbind A`。

## 範圍：預設只看本 session

```tmux
set -g @agent_backlog_scope session   # 預設
set -g @agent_backlog_scope global    # 想看全部就改這個
```

一則待辦就是一個 window，所以「屬於哪個 session」＝**那個 window 現在住在哪個
session**。不另外記「由誰建立」—— window 幾乎不會被 `move-window` 搬走，
而且「東西在哪就歸哪」比較直覺。

清單裡按 **`Tab`** 可以即時在「本 session／全部」之間切，標題列會顯示現在是哪個模式：

```
  3/3 則  · 本 session（Tab 看全部）
  5/5 則  · 全部 session（Tab 切回本 session）
```

**agent 那側（MCP）跟著一起 scope。** 它從繼承來的 `TMUX_PANE` 反推自己在哪個
session —— 不這樣做的話，你看到 0 則、agent 看到 11 則，就違反了
「人和 agent 看同一份」這個前提。Claude Code 不是在 tmux 裡跑（沒有 `TMUX_PANE`）
就退回全域。

選 `global` 時，按 `Enter` 若那則在別的 session，會 `switch-client` 把你帶過去
（只做 `select-window` 的話你的 client 會留在原地，看起來像沒反應）。

範圍的外緣是**同一台機器的同一個 tmux server**。不同 server（不同 `TMUX_TMPDIR`）
彼此看不到。

## 資料存在哪

| option | 內容 |
|---|---|
| `@agent_backlog_prompt` | 原始 markdown（派工時直接當 prompt） |
| `@agent_backlog_status` | pending / running / blocked / done（任意字串） |

「是不是待辦」的判斷 = **有沒有 `@agent_backlog_prompt`**。

```sh
# 自己查
tmux list-windows -a -f '#{!=:#{@agent_backlog_prompt},}' \
  -F '#{window_id} #{@agent_backlog_status} #{window_name}'
```

## 已知限制

- **重開機／tmux server 掛掉，待辦就沒了。** 活在 tmux server 記憶體裡，
  目前沒有持久化（規劃見 [docs/04](docs/04-roadmap.md) 階段二）
- **範圍是同一台機器的同一個 tmux server**，不跨機器
- `md.awk` 不 render 表格（要算 East Asian Width）
- 派工需要 `claude` 在**那個 pane 的互動 shell** 的 PATH 裡
- MCP 的 JSON 解析器只認得協定實際用到的那些欄位，不是通用 JSON 函式庫；
  JSON-RPC 的 batch（頂層陣列）不支援

## 移除

```sh
tmux unbind A                                  # 或你自己綁的鍵
tmux kill-window -t '[backlog]' 2>/dev/null
for h in client-resized client-attached client-detached after-resize-pane; do
    tmux set-hook -gu "$h"
done
```

待辦本身是 window，要不要留自己決定。

## 文件

設計脈絡、研究結論、踩過的坑都在 [docs/](docs/)。
實作細節看 [docs/07-implementation.md](docs/07-implementation.md)。
