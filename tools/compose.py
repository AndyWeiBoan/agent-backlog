#!/usr/bin/env python3
"""把左右兩個窗格合成一個畫面。
⚠️ 補空白與截斷都必須用「顯示寬度」，不是字元數 ——
用字元數的話有中文的那幾行分隔線會被推歪。"""
import re, sys
SGR = re.compile(r'\x1b\[[0-9;]*[mKHJ]|\x1b\[\?7[lh]')

def wide(cp):
    return ((0x1100<=cp<=0x115F) or (0x2E80<=cp<=0x303E) or (0x3041<=cp<=0x33FF)
            or (0x3400<=cp<=0x4DBF) or (0x4E00<=cp<=0x9FFF) or (0xA000<=cp<=0xA4CF)
            or (0xAC00<=cp<=0xD7A3) or (0xF900<=cp<=0xFAFF) or (0xFE30<=cp<=0xFE6F)
            or (0xFF00<=cp<=0xFF60) or (0xFFE0<=cp<=0xFFE6) or (0x1F300<=cp<=0x1FAFF)
            or cp in (0x2705,0x2B1B,0x2B1C,0x2B50,0x2B55,0x2329,0x232A))

def dw(s):
    return sum(2 if wide(ord(c)) else 1 for c in SGR.sub('', s))

def clip(s, cols):
    """截到 cols 個顯示格，保留 ANSI（真實終端機 DECAWM 關掉就是這個行為）。"""
    out, w, i = [], 0, 0
    while i < len(s):
        m = SGR.match(s, i)
        if m:
            out.append(m.group(0)); i = m.end(); continue
        cw = 2 if wide(ord(s[i])) else 1
        if w + cw > cols: break
        out.append(s[i]); w += cw; i += 1
    return ''.join(out), w

LEFT_COLS  = 46
RIGHT_COLS = 80
ROWS       = 38      # 整張圖的高度
MIRROR     = 14      # 有第三個檔案時，右下鏡像區佔幾列（含分隔線）

def load(p):
    return [l.rstrip('\r') for l in open(p, encoding='utf-8').read().split('\n')]

left  = load(sys.argv[1])
right = load(sys.argv[2])
# 第三個參數 = 鏡像區的內容（真的 capture-pane 抓下來的 agent 畫面）。
# 給了就把右邊切成上下兩塊，模擬 sync_mirror 開出下半部的樣子。
mirror = load(sys.argv[3]) if len(sys.argv) > 3 else None

if mirror is not None:
    top = ROWS - MIRROR
    bar = '\x1b[38;5;240m' + '─' * RIGHT_COLS + '\x1b[0m'
    # 鏡像區靠下對齊：真的鏡像窗格顯示的是來源畫面的**末尾**（輸入框在最下面）
    m = mirror[-(MIRROR - 1):] if len(mirror) > MIRROR - 1 else \
        [''] * (MIRROR - 1 - len(mirror)) + mirror
    right = (right[:top] + [''] * max(0, top - len(right))) + [bar] + m

res = []
for i in range(ROWS):
    a = left[i]  if i < len(left)  else ''
    b = right[i] if i < len(right) else ''
    a, w = clip(a, LEFT_COLS)
    b, _ = clip(b, RIGHT_COLS)
    res.append(f"{a}\x1b[0m{' ' * (LEFT_COLS - w)}\x1b[38;5;240m│\x1b[0m {b}\x1b[0m")
sys.stdout.write('\n'.join(res))
