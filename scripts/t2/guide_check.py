#!/usr/bin/env python3
"""guide_check.py -- deterministic QA for the T2 guide (documentation tool, no Vivado needed)

  python scripts/t2/guide_check.py ledger   <file-or-dir>        verify evidence-ledger citations against the real files
  python scripts/t2/guide_check.py assemble <parts_dir> <out.md>  join NN_*.md parts, build the table of contents
  python scripts/t2/guide_check.py check    <guide.md>            links, encoding, pending markers, anchors, forbidden claims
  python scripts/t2/guide_check.py mojibake <file>                is this file's text garbled (UTF-8 read as cp1252)?

Exit code 0 = pass, 1 = fail. Reads and writes UTF-8 only.
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# ------------------------------------------------------------------ helpers
def read(p):
    return Path(p).read_text(encoding="utf-8", errors="replace")

def norm_num_text(s):
    """remove thousands separators between digits so '1,451' == '1451'"""
    return re.sub(r"(?<=\d),(?=\d{3}(?!\d))", "", s)

def resolve(path_str):
    p = Path(path_str.strip().strip("`").replace("\\", "/"))
    for cand in (ROOT / p, Path.cwd() / p, p):
        if cand.exists():
            return cand
    return None

MOJI_SUBSTR = ["\u00e2\u20ac", "\u00c3\u2014", "\u00c3\u00a9", "\u00ef\u00bb\u00bf", "\u00ce\u00bc", "\ufffd"]

def mojibake_lines(text):
    bad = []
    for i, line in enumerate(text.splitlines(), 1):
        if all(ord(c) < 128 for c in line):
            continue
        hit = any(m in line for m in MOJI_SUBSTR)
        if not hit:
            try:
                fixed = line.encode("cp1252").decode("utf-8")
                hit = fixed != line
            except (UnicodeEncodeError, UnicodeDecodeError):
                hit = False
        if hit:
            bad.append(i)
    return bad

def slug(h):
    h = h.strip().lower()
    h = re.sub(r"[^\w\s-]", "", h, flags=re.UNICODE)
    return re.sub(r"\s", "-", h)

def headings(text, levels=("## ", "### ")):
    out, fence = [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if not fence and line.startswith(levels):
            out.append(line)
    return out

# ------------------------------------------------------------------ ledger
def cmd_ledger(target):
    t = Path(target)
    files = sorted(t.glob("*.md")) if t.is_dir() else [t]
    if not files or not all(f.exists() for f in files):
        print(f"FAIL: {target} not found / empty"); return 1
    parsed = checked = skipped = 0
    fails = []
    src_re = re.compile(r"`?([\w./\\-]+\.\w{1,5})`?(?::(\d+)(?:-(\d+))?)?")
    for f in files:
        for ln, row in enumerate(read(f).splitlines(), 1):
            if not row.lstrip().startswith("|"):
                continue
            cells = [c.strip() for c in row.strip().strip("|").split("|")]
            if len(cells) < 4 or set("".join(cells)) <= set("-: "):
                continue
            if cells[0].lower() in ("fact", "item", "name"):
                continue
            fact, value, source, marker = cells[0], cells[1], cells[2], cells[3]
            m = src_re.search(source)
            if not m:
                continue
            parsed += 1
            mk = marker.upper()
            if any(k in mk for k in ("COMPUTED", "INFERENCE", "NOT RECORDED", "HUMAN")):
                skipped += 1; continue
            nums = [n for n in re.findall(r"-?\d[\d,]*\.?\d*", value) if len(n.replace(",", "").replace(".", "").replace("-", "")) >= 2]
            if not nums:
                skipped += 1; continue
            src = resolve(m.group(1))
            if src is None:
                fails.append((f.name, ln, fact, value, source, "cited file does not exist")); checked += 1; continue
            lines = read(src).splitlines()
            if m.group(2):
                a = int(m.group(2)); b = int(m.group(3) or a)
                window = "\n".join(lines[max(0, a - 4): b + 3])
            else:
                window = "\n".join(lines)
            window = norm_num_text(window)
            missing = [n for n in nums if norm_num_text(n).strip(",") not in window]
            checked += 1
            if missing:
                fails.append((f.name, ln, fact, value, source, f"not found near cited line: {missing}"))
    print(f"ledger rows parsed {parsed}, checked {checked}, skipped (computed/inference/no number) {skipped}, FAILED {len(fails)}")
    for f, ln, fact, value, source, why in fails[:60]:
        print(f"  {f}:{ln}  {fact!r} = {value!r}  cites {source}  -> {why}")
    if parsed == 0:
        print("FAIL: no ledger rows recognised (expected table rows: fact | value | source path[:line] | marker)")
        return 1
    print("LEDGER PASS" if not fails else "LEDGER FAIL")
    return 0 if not fails else 1

# ------------------------------------------------------------------ assemble
def cmd_assemble(parts_dir, out):
    d = Path(parts_dir)
    parts = sorted(p for p in d.glob("*.md") if re.match(r"^\d\d.*\.md$", p.name))
    if not parts:
        print(f"FAIL: no NN_*.md parts in {parts_dir}"); return 1
    texts = [read(p).rstrip() for p in parts]
    body = "\n\n".join(texts) + "\n"
    if "<!-- TOC -->" in body:
        toc = []
        for h in headings(body):
            lvl = 2 if h.startswith("## ") else 3
            title = h[lvl + 1:].strip()
            toc.append(("  " if lvl == 3 else "") + f"- [{title}](#{slug(title)})")
        body = body.replace("<!-- TOC -->", "\n".join(toc), 1)
    Path(out).write_text(body, encoding="utf-8", newline="\n")
    print(f"assembled {len(parts)} parts -> {out} ({len(body.encode('utf-8')) / 1024:.1f} KB)")
    for p in parts:
        print(f"  {p.name:40} {p.stat().st_size / 1024:6.1f} KB")
    return 0

# ------------------------------------------------------------------ check
ANCHORS = [
    ("partial bitstream bytes", ["585559"]), ("full bitstream bytes", ["4045666"]),
    ("predicted partial bytes", ["585560"]), ("predicted full bytes", ["4045667"]),
    ("JTAG clock", ["15000000", "15 MHz", "15MHz"]), ("partial swap mean ms", ["429.3"]),
    ("full program mean ms", ["2500.5"]),
    ("WNS int16", ["2.135"]), ("WNS int8", ["1.481"]), ("WNS int4/grey", ["2.981"]), ("WHS", ["0.088"]),
    ("U_RP LUT int16", ["253"]), ("U_RP LUT int8", ["1451"]), ("U_RP LUT int4", ["693"]), ("U_RP LUT grey", ["179"]),
    ("partition pins", ["180"]), ("static LUT", ["1300"]), ("static FF", ["2659"]),
    ("sim cycles", ["CT_CYCLES"]), ("OOC int8 LUT", ["1442"]), ("OOC int4 LUT", ["597"]),
    ("accumulator widths", ["18 bit", "18-bit", "18 bits"]),
    ("Pblock slices", ["SLICE_X80Y50:SLICE_X103Y99"]), ("Pblock DSP", ["DSP48_X3Y20:DSP48_X4Y39"]),
    ("Pblock RAMB18", ["RAMB18_X4Y20:RAMB18_X4Y39"]), ("Pblock RAMB36", ["RAMB36_X4Y10:RAMB36_X4Y19"]),
    ("config column", ["RPM_X 205", "RPM_X205"]), ("clock region", ["X1Y1"]),
    ("demo rows", ["144"]), ("self-test case checks", ["58/58", "58 / 58"]),
    ("lab programs", ["23 programs", "23 program"]), ("pr_verify", ["pr_verify"]),
]
FORBIDDEN = [r"MNIST accuracy", r"\bmW\b", r"\bwatts?\b", r"power measured", r"energy per", r"Fmax of"]

def cmd_check(guide):
    g = Path(guide)
    if not g.exists():
        print(f"FAIL: {guide} not found"); return 1
    text = read(g)
    flat = norm_num_text(text)
    fail = 0
    print(f"size {len(text.encode('utf-8')) / 1024:.1f} KB, {len(text.splitlines())} lines, "
          f"{len(headings(text, ('## ',)))} level-2 sections, {text.count('![')} figures")
    # pending markers
    pend = [i for i, l in enumerate(text.splitlines(), 1) if re.search(r"\(pending\)|\bTODO\b|\bTBD\b|<!-- *PENDING", l)]
    print(f"pending/TODO markers: {len(pend)}" + (f" at lines {pend[:15]}" if pend else ""))
    fail += bool(pend)
    # encoding
    bad = mojibake_lines(text)
    print(f"garbled-text lines: {len(bad)}" + (f" at lines {bad[:15]}" if bad else ""))
    fail += bool(bad)
    if text.startswith("\ufeff"):
        print("note: file starts with a BOM (harmless)")
    # links
    missing = []
    for m in re.finditer(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)", text):
        tgt = m.group(1)
        if tgt.startswith(("http://", "https://", "mailto:", "#")):
            continue
        tgt = tgt.split("#")[0]
        if tgt and not (g.parent / tgt).exists():
            missing.append(tgt)
    print(f"broken relative links/images: {len(missing)}" + (f" {sorted(set(missing))[:10]}" if missing else ""))
    fail += bool(missing)
    # anchors
    absent = [lab for lab, alts in ANCHORS if not any(norm_num_text(a) in flat for a in alts)]
    print(f"anchor facts missing: {len(absent)}" + (f" {absent}" if absent else ""))
    fail += bool(absent)
    # forbidden claims (warn: must be reviewed by a human; legit only in limits / T3 sections)
    hits = []
    for pat in FORBIDDEN:
        for i, l in enumerate(text.splitlines(), 1):
            if re.search(pat, l, re.I):
                hits.append((i, pat))
    print(f"claim-risk phrases (review each; allowed only in the limits and T3 sections): {len(hits)}" + (f" {hits[:12]}" if hits else ""))
    # evidence markers
    for tag in ("[MEASURED]", "[COMPUTED]", "[PREDICTED]", "[INFERENCE]", "[NOT RECORDED]", "[HUMAN-REPORTED]"):
        print(f"  {tag:18} {text.count(tag)}")
    print("GUIDE CHECK PASS" if not fail else "GUIDE CHECK FAIL")
    return 1 if fail else 0

def cmd_mojibake(path):
    p = Path(path)
    if not p.exists():
        print(f"FAIL: {path} not found"); return 1
    raw = p.read_bytes()
    text = raw.decode("utf-8", errors="replace")
    bad = mojibake_lines(text)
    print(f"{path}: {len(raw)} bytes, BOM {'yes' if raw.startswith(b'\xef\xbb\xbf') else 'no'}, garbled lines {len(bad)}" + (f" at {bad[:10]}" if bad else ""))
    print("TEXT CLEAN" if not bad else "TEXT GARBLED")
    return 1 if bad else 0

# ------------------------------------------------------------------ main
def main(argv):
    if len(argv) >= 3 and argv[1] == "ledger":
        return cmd_ledger(argv[2])
    if len(argv) >= 4 and argv[1] == "assemble":
        return cmd_assemble(argv[2], argv[3])
    if len(argv) >= 3 and argv[1] == "check":
        return cmd_check(argv[2])
    if len(argv) >= 3 and argv[1] == "mojibake":
        return cmd_mojibake(argv[2])
    print(__doc__)
    return 2

if __name__ == "__main__":
    sys.exit(main(sys.argv))
