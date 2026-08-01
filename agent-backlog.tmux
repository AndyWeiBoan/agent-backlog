#!/usr/bin/env sh
# TPM 入口。TPM 的定義就是「一個 git repo ＋ 至少一個可執行的 *.tmux」，
# 安裝時把它 source 一遍就完事。
#
# 刻意先綁 prefix + A，不碰舊版的 C-/ / C-_ / prefix P ——
# 新舊兩套要能同時活著，回滾只是「不按這個鍵」。

DIR="$(cd "$(dirname "$0")" && pwd)"

tmux bind-key A run-shell "sh '$DIR/scripts/open.sh'"
