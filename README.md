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

`prefix + A` 開清單。

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

自己綁的話，路徑可以從 `@agent_backlog_path` 拿：

```tmux
set -g @agent_backlog_no_key on
bind-key -n C-o run-shell "sh #{@agent_backlog_path}/scripts/open.sh"
```

## 從舊版 action-items 遷移

舊版用的是沒有 namespace 的 `@prompt` / `@status`，新版用
`@agent_backlog_prompt` / `@agent_backlog_status`。

```sh
sh scripts/migrate.sh
```

**刻意不刪舊 key** —— 新舊兩套可以同時活在同一個 tmux server 上，
互不干擾（filter 各看各的 key），回滾只是「不按那個鍵」。
確認新版穩了之後再自己清掉舊 key。

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
