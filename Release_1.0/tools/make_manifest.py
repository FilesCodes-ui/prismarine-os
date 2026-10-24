#!/usr/bin/env python3
"""Rebuild manifest.txt for a Prismarine release folder (run inside release/).
VERSION RULE: every change raises the version number.
   python3 tools/make_manifest.py          raises it by 0.1 (1.0 -> 1.1 -> 1.2 ...)
   python3 tools/make_manifest.py major    next whole number (1.7 -> 2.0)
   python3 tools/make_manifest.py 1.5      set an exact number
Hashes every system file, and builds the store list from store/store.json.
In store.json, "sha256" and "size" are optional; leave them out to skip the check
(or set "auto": true to have this script fill them in for local "file" entries)."""
import hashlib, json, os, sys
import re
def next_version(arg):
    cur = (0, 9)
    try:
        m = re.search(r'version = "Release (\d+)\.(\d+)"', open("manifest.txt").read())
        if m: cur = (int(m.group(1)), int(m.group(2)))
    except OSError:
        pass
    if arg and re.fullmatch(r"\d+\.\d+", arg):
        a, b = arg.split("."); return "Release %d.%d" % (int(a), int(b))
    if arg == "major":
        return "Release %d.0" % (cur[0] + 1)
    return "Release %d.%d" % (cur[0], cur[1] + 1)
ver = next_version(sys.argv[1] if len(sys.argv) > 1 else None)
h = lambda b: hashlib.sha256(b).hexdigest()
files = {}
for r, _, fs in os.walk("."):
    for f in fs:
        p = os.path.join(r, f)[2:].replace(os.sep, "/")
        if p == "startup.lua" or (p.startswith("prismarine/") and p != "prismarine/apps/archive.lua"):
            files[p] = h(open(p, "rb").read())
q = lambda s: json.dumps(s)
out = ["{", "  version = %s," % q(ver), "  files = {"]
out += ["    [%s] = %s," % (q(p), q(files[p])) for p in sorted(files)]
out += ["  },", "  addons = {",
        "    archive = { path = \"prismarine/apps/archive.lua\", sha256 = %s }," % q(h(open("prismarine/apps/archive.lua", "rb").read())),
        "  },", "  store = {"]
for e in json.load(open("store/store.json")):
    if e.get("auto") and e.get("file"):
        d = open(e["file"], "rb").read(); e["sha256"], e["size"] = h(d), len(d)
    e.pop("auto", None)
    keys = ["name", "about", "dest", "sha256", "size", "file", "url"]
    out.append("    { " + ", ".join("%s = %s" % (k, q(e[k])) for k in keys if k in e) + " },")
out += ["  },", "}"]
open("manifest.txt", "w").write("\n".join(out) + "\n")
print("manifest.txt written:", len(files), "files, version", ver)
