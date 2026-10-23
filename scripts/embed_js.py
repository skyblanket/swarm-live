#!/usr/bin/env python3
"""Embed a JS file in an sw module as a string function.

  python3 scripts/embed_js.py src/arena.js ArenaJs src/ArenaJs.sw

sw string literals take \\" and \\n; the JS must not contain backslashes
(use single quotes / char codes) or the sw sequence '{{}}' is irrelevant
here but keep it out anyway.
"""
import sys
src, mod, out = sys.argv[1:4]
js = open(src).read()
assert "\\" not in js, "arena JS must not contain backslashes"
lines = js.split("\n")
# swc segfaults on one very long "..." ++ chain (skyblanket/swarmrt: ~900 operands), so the
# string is split into parts of at most 200 lines, each its own function
CHUNK = 200
parts = []
for k in range(0, len(lines), CHUNK):
    body = []
    for ln in lines[k:k + CHUNK]:
        esc = ln.replace('"', '\\"')
        body.append('    "' + esc + '\\n" ++')
    parts.append("fun part%d() {\n%s\n    \"\"\n}\n" % (len(parts), "\n".join(body)))
joined = " ++ ".join("part%d()" % i for i in range(len(parts)))
text = "module %s\n\n# GENERATED from %s by scripts/embed_js.py - edit the .js, not this file.\n\nexport [js]\n\nfun js() { %s }\n\n%s" % (mod, src, joined, "\n".join(parts))
open(out, "w").write(text)
print("wrote", out, len(lines), "lines")
