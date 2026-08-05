# 流程圖：mermaid flowchart / graph（TD 方向）→ 文字
#
# 佈局 = Sugiyama 的前三步：斷環 → 分層（最長路徑）→ 跨層邊插虛擬節點。
# 刻意不做第四步（交叉最小化）：那要迭代重排，而在字元格裡就算排好了繞線還是會撞，
# 投資報酬率很差。一層放五個以上的節點會變吵 —— 那是這個做法的上限。
#
# 佈局交給 graph.awk 的分層引擎（ER 與 C4 也用同一支）——
# 這個檔只負責把 mermaid 的語法解析成節點與邊。
#
# 認不出來就回 ""，md.awk 照 code block 畫。
# 依賴 width.awk 與 graph.awk。

function flow_render(buf, n,   bi, line, prev, elab, edot, key, lab, shape, ce, arrow, i, seen) {
    gr_reset()
    seen = 0
    # ── 解析 ──
    for (bi = 1; bi <= n; bi++) {
        line = buf[bi]; gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line == "") continue
        if (line ~ /^(flowchart|graph)[ \t]/) { seen = 1; continue }
        if (line ~ /^(subgraph|end)([ \t]|$)/) continue    # subgraph 先當群組標籤忽略
        if (line ~ /^%%/) continue
        prev = 0; elab = ""; edot = 0
        # 一行可以串多段：A[x] -->|lab| B(y) --> C{z}
        while (length(line) > 0) {
            if (!match(line, /^[A-Za-z0-9_.-]+/)) break
            key = substr(line, 1, RLENGTH); line = substr(line, RLENGTH+1)
            lab = ""; shape = "["
            if      (substr(line,1,2) == "((") { shape="(("; ce=index(line,"))"); lab=substr(line,3,ce-3); line=substr(line,ce+2) }
            else if (substr(line,1,2) == "[[") { shape="[["; ce=index(line,"]]"); lab=substr(line,3,ce-3); line=substr(line,ce+2) }
            else if (substr(line,1,2) == "([") { shape="(["; ce=index(line,"])"); lab=substr(line,3,ce-3); line=substr(line,ce+2) }
            else if (substr(line,1,2) == "[(") { shape="[("; ce=index(line,")]"); lab=substr(line,3,ce-3); line=substr(line,ce+2) }
            else if (substr(line,1,1) == "[")  { shape="[";  ce=index(line,"]");  lab=substr(line,2,ce-2); line=substr(line,ce+1) }
            else if (substr(line,1,1) == "(")  { shape="(";  ce=index(line,")");  lab=substr(line,2,ce-2); line=substr(line,ce+1) }
            else if (substr(line,1,1) == "{")  { shape="{";  ce=index(line,"}");  lab=substr(line,2,ce-2); line=substr(line,ce+1) }
            gsub(/^["']|["']$/, "", lab)
            i = gr_node(key)
            if (lab != "") { GR_T[i] = lab; GR_SH[i] = (shape == "(" || shape == "([" || shape == "((") ? "(" : (shape == "{" ? "{" : "[") }
            gsub(/^[ \t]+/, "", line)
            if (prev > 0) { gr_edge(prev, i, elab, edot); seen = 1 }
            prev = i; elab = ""; edot = 0
            if (!match(line, /^(-\.-+>?|-+>|=+>|-+)/)) break
            arrow = substr(line, 1, RLENGTH); line = substr(line, RLENGTH+1)
            edot = (arrow ~ /\./)
            gsub(/^[ \t]+/, "", line)
            if (substr(line,1,1) == "|") { ce = index(substr(line,2), "|"); elab = substr(line,2,ce-1); line = substr(line,ce+2) }
            gsub(/^[ \t]+/, "", line)
        }
    }
    if (!seen || GR_NN == 0 || GR_NE == 0) return ""
    return gr_render()
}
