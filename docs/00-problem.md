# 00 — 要解決什麼問題

## 問題陳述（使用者原話）

> 在與 agent 討論過程中會產生一些 action item，或是有些內容值得轉化成 action item。
> 我們需要有個機制讓**使用者與 agent 看到**有哪些待處理事項。
> 這些事項可以在 main agent or other agent 來執行，**main agent 負責統籌分配**。

拆成四個要求：

1. **共享可見** —— 人和 agent 看的是同一份清單，不是兩份要同步的資料
2. **可轉化** —— 對話中冒出「這件事該做」時，能立刻記下來且不打斷當前工作
3. **可派工** —— 一則待辦可以交給獨立的 agent 實例去執行
4. **可接手** —— 派出去之後，人能直接進去跟那個 agent 對話

## 為什麼不用 Claude Code 內建的 TodoWrite / Task

用途根本不同：

| | 內建 TodoWrite | 本專案 |
|---|---|---|
| 生命週期 | 單一 session 內 | 跨 session、跨 agent |
| 誰看得到 | 只有那個 agent（人看得到摘要） | 人與所有 agent |
| 能否派工 | 不能 | 可以，開獨立實例執行 |
| 人能否接手 | 不能 | 可以 attach 進去直接對話 |

內建那份是「單一 session 內的步驟追蹤」，這份是「工作項目」。兩者可以並存。

> ⚠️ 命名上刻意避開 `todo` —— 叫 todo 會讓 Claude 混淆成內建的 TodoWrite。

## 為什麼不用 `/background`

使用者明確否決：

> 我建議還是在 tmux 不要 `/background`，我認為這樣才平等，我們能夠用一樣的手段操作。
> 如果是在 background 我很難操作，關掉 claude code 我會很麻煩，對我不公平。

核心是**對等性**：人和 agent 應該用同一套手段操作同一個東西。background task 是 agent
專屬的、人碰不到的，違反這點。

## 核心設計決策：一則待辦 = 一個 tmux window

```
window 名稱  →  標題
@prompt      →  內容（派工時直接當 prompt）
@status      →  pending / running / blocked / done
```

**沒有資料庫、沒有檔案 store。清單就是 window 列表。**

這個決策的價值：「待辦」與「執行它的地方」是**同一個物件**，所以不會有兩份狀態要同步。
`list` 回報的「裡面在跑什麼」是 tmux 直接查 `pane_current_command` 得到的現實
（`zsh` = 還沒開始，`claude` = 正在跑），不是我們自己記的、會脫節的欄位。

### 這個決策的代價

- **20 則待辦 = 20 個閒置 window**，window list 會很長
- **重開機就消失** —— item 活在 tmux server 記憶體裡
- 範圍限於「同一台機器的同一個 tmux server」，不跨機器

前兩點在 [04-roadmap.md](04-roadmap.md) 有對應規劃。長期保存仍應該用 Jira。

## 為什麼需要 MCP 而不只是 shell script

功能上 shell script 就做得到。但**新的 Claude Code session 不會知道那支 script 存在** ——
使用者得每次交代路徑和用法。

註冊成 MCP 之後，每個 session 啟動就載入 tool 與說明，agent 自己就知道有這份清單、
知道能派工。**MCP 買的是「可發現性」，不是功能。**

（這一點在討論中被漏掉過一次，導致方向錯誤。記在這裡避免重蹈。）

## 設計原則

1. **對等** —— 人能做的 agent 也能做，反之亦然
2. **單一事實來源** —— 不維護第二份狀態；能從 tmux 查到的就不要自己記
3. **簡單優先** —— 使用者多次以此否決過度設計的方案（見下）
4. **失敗要看得見** —— popup 裡的錯誤不能一閃而過（`display-popup -E` 會在指令結束時關閉）

### 被否決過的方案（避免重提）

| 方案 | 否決理由 |
|---|---|
| nvim 當 buffer store + proxy plugin | 「既然要讀檔案就不要透過 nvim，這不是脫褲子放屁？」 |
| `/background` | 不對等，人難以操作 |
| JSON 檔案 store | 與 window 狀態會有兩份，需要同步 |
| 一開始就上 fzf | 當時 `prefix w` 已經夠用（**後來因為要 live preview 才重新引入**） |
| reset-then-accumulate 的旗標式寫法 | 「這很難閱讀你懂嗎，很繞」——> 改成兩個具名函式 |
