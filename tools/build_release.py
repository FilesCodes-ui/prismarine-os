#!/usr/bin/env python3
"""Prismarine OS release tool. Run it from the repo root.

  python tools/build_release.py manifest 23 --tree os --data-format 2
  python tools/build_release.py verify

manifest  scans the tree folder (default: os) and writes manifest.json in the
          repo root. Paths inside the tree become paths on the computer:
          os/startup.lua installs as startup.lua.
          Commit manifest.json with the files, then tag that commit pv<N>
          and publish a GitHub release for the tag.
verify    checks every manifest entry exists and matches its SHA-256.
"""
import argparse, hashlib, json, re, sys
from pathlib import Path

ROOT = Path.cwd()
BOOTSTRAP = "startup.lua"
DEFAULT_KEEP = [".simpleos_settings", ".simpleos_secure", "prismarine/data/"]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def safe_path(p):
    parts = p.split("/")
    return bool(p) and not p.startswith("/") and ".." not in parts and "." not in parts \
        and "" not in parts and not re.search(r"[\x00-\x1f\\]", p)


def manifest(a):
    tree = (ROOT / a.tree).resolve()
    if not (tree / BOOTSTRAP).is_file():
        sys.exit(f"{tree} has no {BOOTSTRAP}")
    files = []
    for f in sorted(p for p in tree.rglob("*") if p.is_file()):
        rel = f.relative_to(tree).as_posix()
        src = f.relative_to(ROOT).as_posix()
        if not safe_path(rel) or not safe_path(src):
            sys.exit(f"unsafe path: {rel}")
        files.append({"path": rel, "src": src, "sha256": sha(f), "size": f.stat().st_size})
    data = {"format": 1, "version": a.version, "dataFormat": a.data_format,
            "bootstrap": BOOTSTRAP, "keep": a.keep if a.keep is not None else DEFAULT_KEEP,
            "files": files}
    out = ROOT / "manifest.json"
    out.write_text(json.dumps(data, indent=2) + "\n")
    print(f"pv{a.version}: {len(files)} files")
    print("manifest sha256:", sha(out))
    print(f"next: commit, then tag pv{a.version} and publish a release for the tag")


def verify(_a):
    m = ROOT / "manifest.json"
    if not m.is_file():
        sys.exit("no manifest.json")
    data = json.loads(m.read_text())
    bad = 0
    for f in data["files"]:
        p = ROOT / f["src"]
        if not safe_path(f["path"]) or not safe_path(f["src"]):
            print("unsafe path", f["path"]); bad += 1
        elif not p.is_file():
            print("missing", f["src"]); bad += 1
        elif sha(p) != f["sha256"]:
            print("changed since the manifest was built:", f["src"]); bad += 1
    print(f"pv{data['version']}:", "OK" if not bad else f"{bad} problems")
    sys.exit(1 if bad else 0)


ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
sub = ap.add_subparsers(dest="cmd", required=True)
b = sub.add_parser("manifest"); b.add_argument("version", type=int)
b.add_argument("--tree", default="os"); b.add_argument("--data-format", type=int, default=1)
b.add_argument("--keep", nargs="*", default=None); b.set_defaults(fn=manifest)
sub.add_parser("verify").set_defaults(fn=verify)
a = ap.parse_args(); a.fn(a)
