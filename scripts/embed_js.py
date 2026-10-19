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
body = []
for ln in lines:
    esc = ln.replace('"', '\\"')
    body.append('    "' + esc + '\\n" ++')
text = "module %s\n\n# GENERATED from %s by scripts/embed_js.py - edit the .js, not this file.\n\nexport [js]\n\nfun js() {\n%s\n    \"\"\n}\n" % (mod, src, "\n".join(body))
open(out, "w").write(text)
print("wrote", out, len(lines), "lines")
