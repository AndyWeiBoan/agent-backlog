#!/usr/bin/env python3
"""ANSI（SGR）→ SVG。零外部依賴，只用標準庫。
把真實的終端機輸出畫成 SVG —— 比截圖精確，而且可以進版控 diff。"""
import sys, re, html

def xterm256(n):
    if n < 16:
        base = ["#000000","#cd0000","#00cd00","#cdcd00","#0000ee","#cd00cd","#00cdcd","#e5e5e5",
                "#7f7f7f","#ff0000","#00ff00","#ffff00","#5c5cff","#ff00ff","#00ffff","#ffffff"]
        return base[n]
    if n < 232:
        n -= 16
        lv = [0,95,135,175,215,255]
        return "#%02x%02x%02x" % (lv[n//36], lv[(n//6)%6], lv[n%6])
    v = 8 + (n-232)*10
    return "#%02x%02x%02x" % (v,v,v)

FG, BG = "#d8d8d8", "#0c0c0c"
SGR = re.compile(r"\x1b\[([0-9;]*)m")

def wide(cp):
    return ((0x1100<=cp<=0x115F) or (0x2E80<=cp<=0x303E) or (0x3041<=cp<=0x33FF)
            or (0x3400<=cp<=0x4DBF) or (0x4E00<=cp<=0x9FFF) or (0xA000<=cp<=0xA4CF)
            or (0xAC00<=cp<=0xD7A3) or (0xF900<=cp<=0xFAFF) or (0xFE30<=cp<=0xFE6F)
            or (0xFF00<=cp<=0xFF60) or (0xFFE0<=cp<=0xFFE6) or (0x1F300<=cp<=0x1FAFF)
            or cp in (0x2705,0x2B1B,0x2B1C,0x2B50,0x2B55,0x2329,0x232A))

def parse(lines):
    """回傳 [(row, col, text, fg, bg, bold, dim, strike)]，col 是顯示格。"""
    out, maxc = [], 0
    for r, line in enumerate(lines):
        fg, bg, bold, dim, strike = FG, None, False, False, False
        col, pos, run = 0, 0, []
        def flush():
            nonlocal run
            if run:
                out.append((r, run[0], "".join(run[1]), fg, bg, bold, dim, strike))
                run = []
        while pos < len(line):
            m = SGR.match(line, pos)
            if m:
                flush()
                # ⚠️ 一定要「按順序消耗」參數，不能各掃一遍。
                # 38;5;N 與 48;5;N 的 N 是**色號**，不是另一個 SGR 指令 ——
                # 分開掃的話 \033[1;38;5;42m 裡的 42 會被當成「綠色背景」，
                # 於是每個字底下鋪一塊綠底、字又是綠的，標題就整個消失。
                # （實際發生過：md.awk 的 ## 標題在圖上變成一塊綠方塊。）
                # 同理 38;5;9 會被誤判成刪除線、38;5;1 成粗體、38;5;2 成 dim。
                pl = [int(p or 0) for p in (m.group(1) or "0").split(";")]
                i = 0
                while i < len(pl):
                    v = pl[i]
                    if v in (38, 48) and i + 1 < len(pl):
                        if pl[i+1] == 5 and i + 2 < len(pl):
                            c = xterm256(pl[i+2]); i += 3
                        elif pl[i+1] == 2 and i + 4 < len(pl):
                            c = "#%02x%02x%02x" % (pl[i+2], pl[i+3], pl[i+4]); i += 5
                        else:
                            i += 1; continue
                        if v == 38: fg = c
                        else:       bg = c
                        continue
                    if v == 0: fg, bg, bold, dim, strike = FG, None, False, False, False
                    elif v == 1: bold = True
                    elif v == 2: dim = True
                    elif v == 9: strike = True
                    elif v == 7: fg, bg = BG, "#c8c8c8"
                    elif v == 39: fg = FG
                    elif v == 49: bg = None
                    elif 30 <= v <= 37: fg = xterm256(v-30)
                    elif 90 <= v <= 97: fg = xterm256(v-90+8)
                    elif 40 <= v <= 47: bg = xterm256(v-40)
                    elif 100 <= v <= 107: bg = xterm256(v-100+8)
                    i += 1
                pos = m.end(); continue
            ch = line[pos]; pos += 1
            if ch == "\x1b":            # 其他 escape：吃掉到字母為止
                while pos < len(line) and not line[pos].isalpha(): pos += 1
                pos += 1; continue
            # ⚠️ 只有純 ASCII 可以合併成一段，其餘一律自己一個元素、自己一個 x。
            #
            # 合併段是靠 textLength 釘寬度的，而 lengthAdjust 預設是 "spacing" ——
            # 它只調**字距**，不調字形。所以只要那段裡有非 ASCII（字型的
            # advance 跟 8.4px 不一樣），字就會被拉開或擠在一起：
            # 方框字元 ─│┌┐ 之間出現縫隙或重疊，看起來就是一團亂碼。
            # 實際發生過：鏡像區那串 "│─┄┊▼◀▶┌┐└┘├┤┼╭╮╰╯◇" 整個糊掉。
            #
            # 逐字放元素檔案會大一點，但每個字都釘在它該在的格子上 ——
            # 那正是這張圖存在的理由（比截圖精確）。
            cp = ord(ch)
            if not (0x20 <= cp <= 0x7E):
                flush()
                out.append((r, col, ch, fg, bg, bold, dim, strike))
                col += 2 if wide(cp) else 1
            else:
                if not run: run = [col, []]
                run[1].append(ch)
                col += 1
        flush()
        maxc = max(maxc, col)
    return out, maxc

def svg(runs, cols, rows, cw=8.4, ch=18.0, pad=14):
    W, H = cols*cw + pad*2, rows*ch + pad*2
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W:.0f}" height="{H:.0f}" '
         f'viewBox="0 0 {W:.0f} {H:.0f}" font-family="Menlo,DejaVu Sans Mono,monospace" font-size="13">',
         f'<rect width="100%" height="100%" rx="7" fill="{BG}"/>']
    for r, c, txt, fg, bg, bold, dim, strike in runs:
        x, y = pad + c*cw, pad + r*ch
        w = sum(2 if wide(ord(k)) else 1 for k in txt) * cw
        if bg:
            o.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{ch:.1f}" fill="{bg}"/>')
        st = [f'fill="{fg}"']
        if bold:   st.append('font-weight="700"')
        if dim:    st.append('opacity="0.55"')
        if strike: st.append('text-decoration="line-through"')
        # textLength 把每一段釘在它應有的寬度上 —— 不靠字型的 advance 剛好對。
        o.append(f'<text x="{x:.1f}" y="{y+ch*0.74:.1f}" textLength="{w:.1f}" '
                 f'{" ".join(st)} xml:space="preserve">{html.escape(txt)}</text>')
    o.append('</svg>')
    return "\n".join(o)

if __name__ == "__main__":
    lines = sys.stdin.read().split("\n")
    while lines and not lines[-1].strip(): lines.pop()
    runs, cols = parse(lines)
    sys.stdout.write(svg(runs, cols, len(lines)))
