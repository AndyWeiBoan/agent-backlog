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

LEFT_COLS = 46
left  = open(sys.argv[1], encoding='utf-8').read().split('\n')
right = open(sys.argv[2], encoding='utf-8').read().split('\n')
left  = [l.rstrip('\r') for l in left]
right = [l.rstrip('\r') for l in right]
rows = max(len(left), len(right))
res = []
for i in range(rows):
    a = left[i]  if i < len(left)  else ''
    b = right[i] if i < len(right) else ''
    a, w = clip(a, LEFT_COLS)
    res.append(f"{a}\x1b[0m{' ' * (LEFT_COLS - w)}\x1b[38;5;240m│\x1b[0m {b}")
sys.stdout.write('\n'.join(res))
