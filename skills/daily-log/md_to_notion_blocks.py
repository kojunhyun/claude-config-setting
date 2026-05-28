#!/usr/bin/env python3
"""
Markdown -> Notion blocks 변환기 (daily-log/weekly-log 공용).
사용법: python3 md_to_notion_blocks.py <file.md>
- YAML frontmatter(---...---) 제거
- #/##/### -> heading_1/2/3
- -, * -> bulleted_list_item / 1. -> numbered_list_item
- ``` fence -> code block (language=plain text)
- | a | b | 연속행 -> table 블록 (구분행 |---| 자동 제외, 첫 행 헤더)
- --- -> divider
- 그 외 -> paragraph
- 인라인 **bold**, `code` 최소 파싱
stdout 으로 Notion blocks JSON 배열 출력. (100블록 청크 분할은 호출측에서)
rich_text content 2000자 초과시 자동 절단.
"""
import sys, json, re

def rich(text):
    """인라인 **bold**, `code` 최소 파싱 -> rich_text 배열."""
    if text == "":
        return []
    out = []
    # 토큰: `code` 또는 **bold** 또는 일반
    pattern = re.compile(r'(`[^`]+`|\*\*[^*]+\*\*)')
    pos = 0
    for m in pattern.finditer(text):
        if m.start() > pos:
            out.append({"type": "text", "text": {"content": text[pos:m.start()][:2000]}})
        tok = m.group(0)
        if tok.startswith('`'):
            out.append({"type": "text", "text": {"content": tok[1:-1][:2000]}, "annotations": {"code": True}})
        else:
            out.append({"type": "text", "text": {"content": tok[2:-2][:2000]}, "annotations": {"bold": True}})
        pos = m.end()
    if pos < len(text):
        out.append({"type": "text", "text": {"content": text[pos:][:2000]}})
    return out or [{"type": "text", "text": {"content": text[:2000]}}]

def strip_frontmatter(lines):
    if lines and lines[0].strip() == '---':
        for i in range(1, len(lines)):
            if lines[i].strip() == '---':
                return lines[i+1:]
    return lines

def parse_table(rows):
    """| a | b | 형태 행 리스트 -> table block. 구분행 제외."""
    def cells(r):
        r = r.strip()
        if r.startswith('|'): r = r[1:]
        if r.endswith('|'): r = r[:-1]
        return [c.strip() for c in r.split('|')]
    body = [r for r in rows if not re.match(r'^\s*\|?[\s:|-]+\|?\s*$', r) or '|' not in re.sub(r'[\s:|-]', '', r)]
    # 구분행(|---|---|) 식별: --- 와 | 만으로 구성
    data = []
    for r in rows:
        stripped = re.sub(r'[\s|:-]', '', r)
        if stripped == '':   # 구분행
            continue
        data.append(cells(r))
    if not data:
        return None
    width = max(len(r) for r in data)
    trows = []
    for r in data:
        r = r + [''] * (width - len(r))
        trows.append({"object": "block", "type": "table_row",
                      "table_row": {"cells": [rich(c) for c in r]}})
    return {"object": "block", "type": "table",
            "table": {"table_width": width, "has_column_header": True,
                      "has_row_header": False, "children": trows}}

def convert(lines):
    blocks = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i].rstrip('\n')
        s = line.strip()
        # 코드펜스
        if s.startswith('```'):
            lang = s[3:].strip() or "plain text"
            buf = []
            i += 1
            while i < n and lines[i].strip() != '```':
                buf.append(lines[i].rstrip('\n')); i += 1
            i += 1
            content = "\n".join(buf)[:2000]
            blocks.append({"object": "block", "type": "code",
                           "code": {"rich_text": [{"type": "text", "text": {"content": content}}],
                                    "language": "plain text"}})
            continue
        # 표 (연속 | 행 수집)
        if s.startswith('|') and '|' in s[1:]:
            tbl = []
            while i < n and lines[i].strip().startswith('|'):
                tbl.append(lines[i].rstrip('\n')); i += 1
            blk = parse_table(tbl)
            if blk: blocks.append(blk)
            continue
        # 빈 줄
        if s == '':
            i += 1; continue
        # 구분선
        if re.match(r'^(---+|\*\*\*+|___+)$', s):
            blocks.append({"object": "block", "type": "divider", "divider": {}})
            i += 1; continue
        # 제목
        m = re.match(r'^(#{1,3})\s+(.*)$', s)
        if m:
            lvl = len(m.group(1))
            key = f"heading_{lvl}"
            blocks.append({"object": "block", "type": key,
                           key: {"rich_text": rich(m.group(2))}})
            i += 1; continue
        # 번호 리스트
        m = re.match(r'^\d+\.\s+(.*)$', s)
        if m:
            blocks.append({"object": "block", "type": "numbered_list_item",
                           "numbered_list_item": {"rich_text": rich(m.group(1))}})
            i += 1; continue
        # 불릿 리스트
        m = re.match(r'^[-*]\s+(.*)$', s)
        if m:
            blocks.append({"object": "block", "type": "bulleted_list_item",
                           "bulleted_list_item": {"rich_text": rich(m.group(1))}})
            i += 1; continue
        # 인용
        if s.startswith('> '):
            blocks.append({"object": "block", "type": "quote",
                           "quote": {"rich_text": rich(s[2:])}})
            i += 1; continue
        # 일반 문단
        blocks.append({"object": "block", "type": "paragraph",
                       "paragraph": {"rich_text": rich(s)}})
        i += 1
    return blocks

def main():
    if len(sys.argv) < 2:
        sys.exit("usage: md_to_notion_blocks.py <file.md>")
    with open(sys.argv[1], encoding='utf-8') as f:
        lines = f.read().splitlines()
    blocks = convert(strip_frontmatter(lines))
    json.dump(blocks, sys.stdout, ensure_ascii=False)

if __name__ == "__main__":
    main()
