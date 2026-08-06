#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""统计 rae.md 的段落指标（口径固定，供文风修订自检使用）。

指标定义（口径，勿随意改动）：
- 段落：非空行（strip 后不为空的行）
- 段长：段落去除全部空白后的字符数
- 均段长：全部段长的平均值
- 短段占比：段长 < 25 的段落占比（百分比）
- 单句段占比：段内句号/问号/感叹号（。！？）数量 == 1 的段落占比
- 超长段数：段长 > 100 的段落数

用法：
    python tools/para_stats.py               # 全书各章统计
    python tools/para_stats.py 7             # 第七章（含各节）
    python tools/para_stats.py 4-7           # 第4~7章

Windows 下中文乱码的解决（二选一，在运行前执行）：
    chcp 65001
    或：set PYTHONIOENCODING=utf-8
脚本内部已尝试将 stdout 设为 UTF-8（sys.stdout.reconfigure）。
"""
import re
import sys

CH_NUM = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
          '六': 6, '七': 7, '八': 8, '九': 9, '十': 10, '十一': 11}


def load_lines(path='rae.md'):
    with open(path, encoding='utf-8-sig') as f:
        return f.read().split('\n')


def stats(seg):
    """对一段行序列返回统计字典；空返回 None。"""
    paras = [p for p in seg if p.strip()]
    if not paras:
        return None
    lens = [len(re.sub(r'\s', '', p)) for p in paras]

    def nsent(p):
        return len(re.findall(r'[。！？]', p))

    return {
        'n': len(paras),
        'avg': sum(lens) / len(lens),
        'short': sum(1 for l in lens if l < 25) / len(paras) * 100,
        'single': sum(1 for p in paras if nsent(p) == 1) / len(paras) * 100,
        'long': sum(1 for l in lens if l > 100),
    }


def fmt(s):
    return (f"{s['n']:>4}段  均段长{s['avg']:>5.0f}字  "
            f"短段{s['short']:>4.0f}%  单句段{s['single']:>4.0f}%  "
            f"超长段{s['long']:>3}")


def chapter_no(title):
    m = re.match(r'^第([一二三四五六七八九十]+)章', title)
    if m:
        return CH_NUM.get(m.group(1), 0)
    return 0


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
    arg = sys.argv[1] if len(sys.argv) > 1 else 'all'
    lines = load_lines()

    # 章边界（# 开头为章标题）
    chapters = []
    for i, line in enumerate(lines):
        m = re.match(r'^#\s+(.*)', line)
        if m:
            chapters.append((i, m.group(1).strip()))
    chapters.append((len(lines), 'END'))

    # 选择要统计的章
    wanted = []
    if arg == 'all':
        wanted = list(range(len(chapters) - 1))
    else:
        m = re.match(r'^(\d+)(?:-(\d+))?$', arg)
        if m:
            lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
            wanted = [i for i, (idx, t) in enumerate(chapters[:-1])
                      if lo <= chapter_no(t) <= hi]
        else:
            print(f'无法识别的参数: {arg}（用法：全book / 单章号 / 起-止章号）')
            return

    print(f"{'章':<8}{'行数':>6}  {'段落':>4}  {'均段长':>6}  {'短段%':>5}  {'单句段%':>6}  {'超长段':>4}")
    print('-' * 66)
    for i in wanted:
        idx, t = chapters[i]
        e = chapters[i + 1][0]
        s = stats(lines[idx + 1:e])
        if not s:
            continue
        print(f"{t:<8}{e - idx - 1:>6}  {fmt(s)}")
        # 单章时列出各节（## 开头为节标题）
        if arg != 'all':
            secs = [(j, l) for j, l in enumerate(lines)
                    if idx < j < e and l.startswith('## ')]
            for k, (j, l) in enumerate(secs):
                e2 = secs[k + 1][0] if k + 1 < len(secs) else e
                s2 = stats(lines[j + 1:e2])
                if s2:
                    print(f"   {l.strip():<6}{fmt(s2)}")


if __name__ == '__main__':
    main()
