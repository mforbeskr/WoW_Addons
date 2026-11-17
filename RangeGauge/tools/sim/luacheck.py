"""Crude Lua 5.1 sanity check: strips comments/strings, then checks block balance
(function/if/do/repeat vs end/until) and bracket balance per file, reporting where depth breaks."""
import re, sys, glob

def strip(src):
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("--[[", i):
            j = src.find("]]", i)
            i = n if j < 0 else j + 2
        elif src.startswith("--", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src[i] in "\"'":
            q = src[i]; i += 1
            while i < n and src[i] != q:
                i += 2 if src[i] == "\\" else 1
            i += 1
            out.append('""')
        else:
            out.append(src[i]); i += 1
    return "".join(out)

ok = True
for f in sorted(glob.glob(sys.argv[1] + "/*.lua")):
    src = strip(open(f, encoding="utf-8").read())
    depth, line = 0, 1
    paren = {"(": 0, "{": 0, "[": 0}
    for m in re.finditer(r"\n|\b(function|if|do|end|repeat|until|while|for)\b|[(){}\[\]]", src):
        t = m.group(0)
        if t == "\n":
            line += 1; continue
        if t in ("function", "if", "do", "repeat"):
            depth += 1
        elif t in ("end", "until"):
            depth -= 1
            if depth < 0:
                print(f, "extra end at line", line); ok = False; depth = 0
        elif t in "({[":
            paren[t] += 1
        elif t in ")}]":
            paren[{")": "(", "}": "{", "]": "["}[t]] -= 1
    print(f.split("\\")[-1].split("/")[-1], "blocks", depth, "brackets", paren)
    if depth or any(paren.values()):
        ok = False
print("OK" if ok else "PROBLEM")
