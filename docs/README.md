# agent-backlog / docs

人與 agent 共享的待辦清單。這裡放**設計脈絡、研究結論與後續規劃**。

前身是 `~/3rd-party/action-items`（能跑的實作），本專案是它的下一代設計。

## 文件索引

| 檔案 | 內容 |
|---|---|
| [00-problem.md](00-problem.md) | 要解決什麼問題、為什麼不用內建 TodoWrite、設計原則 |
| [01-current-implementation.md](01-current-implementation.md) | `action-items` 現況：資料模型、CLI、MCP、快捷鍵、**這台機器的安裝狀態**、從零重建步驟、**已知 bug**、踩過的坑 |
| [02-research-markdown-renderers.md](02-research-markdown-renderers.md) | 五個 renderer 的實測對照（glow / rich-cli / mdcat / nvim+markview / 自製 awk） |
| [03-research-pure-tmux.md](03-research-pure-tmux.md) | 純 tmux 可行性：`choose-tree` 探測結果、能與不能 |
| [04-roadmap.md](04-roadmap.md) | 三階段規劃與待決策事項 |
| [05-testing.md](05-testing.md) | 開發過程怎麼測（四層策略 ＋ 測試腳本本身的坑） |
| [06-rollback.md](06-rollback.md) | **開發失敗怎麼回到現在能用的狀態**；並存策略避免破壞性遷移 |
| [07-implementation.md](07-implementation.md) | **零依賴版本的實作**：架構、鍵位、效能、驗證過的環境、已知限制 |
| [prototypes/md.awk](prototypes/md.awk) | 自製 markdown renderer 原型（`scripts/md.awk` 是它的正式版） |

## 一句話結論

**已經做出來了。** 441 行、零依賴，在 macOS（tmux 3.6a / BWK awk）與
Alpine（tmux 3.4 / busybox awk / ash）都跑得起來。

原本以為主要障礙是 markdown render，實際做下去發現 render 反而是最順的一段
（`md.awk` 三種 awk 實作輸出逐字元相同）；真正花時間的是**跟終端機、作業系統、
使用者 config 搶鍵**，以及 tmux 版本之間的行為差異。

## 這些文件的寫作原則

**所有效能數字與行為描述都是實測的，不是引用文件。** 研究過程中至少有三次
「官方文件/網路說法」與實際行為不符（見 02、03），所以凡是結論都附上重現方式。
後續維護時若要推翻某個結論，請重跑對應的驗證指令，不要只憑文件。
