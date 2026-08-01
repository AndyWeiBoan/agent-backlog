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
| [prototypes/md.awk](prototypes/md.awk) | 自製 markdown renderer 原型（可執行） |

## 一句話結論

資料層已經 100% 是 tmux 原生的（一則待辦 = 一個 window），所以「做成純 tmux plugin」的
主要障礙不是架構，而是 **markdown render 與語法高亮** —— 而這件事實測證明**可以自己用
awk 寫**，170 行、零依賴、比外部 renderer 快兩個數量級。

## 這些文件的寫作原則

**所有效能數字與行為描述都是實測的，不是引用文件。** 研究過程中至少有三次
「官方文件/網路說法」與實際行為不符（見 02、03），所以凡是結論都附上重現方式。
後續維護時若要推翻某個結論，請重跑對應的驗證指令，不要只憑文件。
