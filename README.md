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

`~/.tmux.conf`：

```tmux
set -g @plugin 'andy/agent-backlog'
```

然後 `prefix + I`。

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
| `@agent_backlog_no_key` | — | 設 `on` 就完全不綁鍵，自己綁 |
| `@agent_backlog_compat` | — | 設 `on` 就連舊版的 `@prompt` / `@status` 一起認 |

自己綁的話，路徑可以從 `@agent_backlog_path` 拿：

```tmux
set -g @agent_backlog_no_key on
bind-key -n C-o run-shell "sh #{@agent_backlog_path}/scripts/open.sh"
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
