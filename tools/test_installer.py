#!/usr/bin/env python3
"""Runs installer_v2.lua against a mock ComputerCraft and a local fake repo.
Needs: pip install lupa. Run from the project root."""
import json, os, shutil, subprocess, sys, tempfile, hashlib
from pathlib import Path
from lupa import LuaRuntime

PROJ = Path(__file__).resolve().parent.parent
INSTALLER = (PROJ / "installer" / "installer_v2.lua").read_text()
fails = 0
ENV = {'tags': {}, 'drafts': [], 'api': True}

def check(name, cond, extra=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + (" " + str(extra) if not cond else ""))
    if not cond: fails += 1

def sh(*a, cwd):
    return subprocess.run([sys.executable, str(PROJ / "tools/build_release.py"), *a],
                          cwd=cwd, capture_output=True, text=True)

def write_tree(tree, v, extra=None, drop=()):
    shutil.rmtree(tree, ignore_errors=True)
    files = {"startup.lua": f'local VERSION = "{v}"\nprint("boot")\n',
             "prismarine/kernel/kernel.lua": "return 1\n",
             "prismarine/apps/messenger.lua": "return 2\n"}
    files.update(extra or {})
    for d in drop: files.pop(d, None)
    for p, c in files.items():
        (tree / p).parent.mkdir(parents=True, exist_ok=True); (tree / p).write_text(c)

def tag(repo, work, name):
    snap = work / ("tag_" + name)
    shutil.copytree(repo, snap)
    ENV["tags"][name] = snap

def run_installer(repo, comp, args, keys="", lines=(), tamper=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    out = []
    keyq = list(keys); lineq = list(lines)
    def p(s): return comp / str(s).lstrip("/")
    def to_lua(v):
        if isinstance(v, dict):
            t = lua.table()
            for k, x in v.items(): t[k] = to_lua(x)
            return t
        if isinstance(v, list): return lua.table(*[to_lua(x) for x in v])
        return v
    def from_lua(t):
        if lua.eval("function(x) return type(x) end")(t) != "table": return t
        ks = list(t.keys())
        if ks and all(isinstance(k, int) for k in ks) and sorted(ks) == list(range(1, len(ks) + 1)):
            return [from_lua(t[i]) for i in range(1, len(ks) + 1)]
        if not ks: return []
        return {k: from_lua(t[k]) for k in ks}
    class W:
        def __init__(s, f): s.f = f
        def write(s, d): s.f.write(d.encode("latin-1") if isinstance(d, str) else d)
        def close(s): s.f.close()
    class R:
        def __init__(s, b): s.b = b
        def readAll(s): return s.b.decode("latin-1")
        def close(s): pass
    def fs_open(path, mode):
        f = p(path)
        if "w" in mode:
            f.parent.mkdir(parents=True, exist_ok=True); return W(open(f, "wb"))
        return R(f.read_bytes()) if f.is_file() else None
    def fs_delete(path):
        f = p(path)
        if f.is_dir(): shutil.rmtree(f)
        elif f.exists(): f.unlink()
    def fs_copy(a, b):
        a, b = p(a), p(b)
        if b.exists(): raise Exception("destination exists")
        b.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(a, b) if a.is_dir() else shutil.copy2(a, b)
    def fs_move(a, b):
        a, b = p(a), p(b)
        if b.exists(): raise Exception("destination exists")
        b.parent.mkdir(parents=True, exist_ok=True); shutil.move(str(a), str(b))
    def getdir(path):
        s = str(path).strip("/"); return s.rsplit("/", 1)[0] if "/" in s else ""
    class Resp:
        def __init__(s, code, body=b""): s.c, s.b = code, body
        def getResponseCode(s): return s.c
        def readAll(s): return s.b.decode("latin-1")
        def close(s): pass
    def http_get(url, headers=None, binary=None):
        if not isinstance(url, str):
            url = url["url"]
        base = "https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/"
        api = "https://api.github.com/repos/FilesCodes-ui/prismarine-os/"
        if url.startswith(api):
            if not ENV["api"]: return None, "rate limited", None
            if "/releases" in url:
                items = [{"tag_name": t, "draft": False} for t in ENV["tags"]] + [{"tag_name": t, "draft": True} for t in ENV["drafts"]]
                return Resp(200, json.dumps(items).encode())
            if "/contents" in url:
                return Resp(200, json.dumps([{"name": f.name} for f in repo.iterdir()]).encode())
        if url.startswith(base):
            ref, _, path = url[len(base):].partition("/")
            root = repo if ref == "main" else ENV["tags"].get(ref)
            if root is None: return None, "404", Resp(404)
            f = root / path.split("?")[0]
            if tamper and f.name == tamper[0] and f.is_file():
                return Resp(200, tamper[1].encode())
            if f.is_file(): return Resp(200, f.read_bytes())
            return None, "404", Resp(404)
        return None, "blocked", None
    events = {"reboot": 0}
    def pull(*a):
        if not keyq: raise Exception("test ran out of keys")
        return "key", {"y": 21, "n": 49}[keyq.pop(0)]
    g = lua.globals()
    g.fs = to_lua({}); 
    for k, f in dict(open=fs_open, exists=lambda x: p(x).exists(), isDir=lambda x: p(x).is_dir(),
                     makeDir=lambda x: p(x).mkdir(parents=True, exist_ok=True) if str(x) else None,
                     delete=fs_delete, copy=fs_copy, move=fs_move, getDir=getdir,
                     isReadOnly=lambda x: False,
                     list=lambda x: to_lua(sorted(os.listdir(p(x))))).items():
        g.fs[k] = f
    g.http = lua.table(get=http_get)
    g.textutils = lua.table(
        unserialiseJSON=lambda s: to_lua(json.loads(s)) if s else None,
        serialiseJSON=lambda t: json.dumps(from_lua(t)))
    g.keys = lua.table(y=21, n=49, q=16, up=200, down=208, enter=28, backspace=14)
    g.colors = lua.eval("setmetatable({}, {__index=function(t,k) return 1 end})")
    g.term = lua.eval("""{getSize=function() return 51,19 end, setCursorPos=function() end,
        getCursorPos=function() return 1,1 end, clearLine=function() end, clear=function() end,
        setTextColor=function() end, setBackgroundColor=function() end, write=function() end,
        isColor=function() return true end}""")
    g.__out = lambda s: out.append(str(s))
    g.__pull = pull
    g.__read = lambda *a: lineq.pop(0)
    g.__reboot = lambda: events.__setitem__("reboot", events["reboot"] + 1)
    lua.execute("""
    print = function(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end __out(table.concat(t,' ')) end
    write = function(s) __out(s) end
    os.pullEvent = __pull; os.pullEventRaw = function() return 'simpleos_yield' end; os.queueEvent = function() end
    os.epoch = function() return 1 end; os.reboot = __reboot
    sleep = function() end; read = __read
    bit32 = {
      band=function(a,b) return a & b end, bor=function(...) local r=0 for _,v in ipairs({...}) do r=r|v end return r end,
      bxor=function(...) local r=0 for _,v in ipairs({...}) do r=r~v end return r end,
      bnot=function(a) return (~a) & 0xffffffff end,
      lshift=function(a,n) return (a<<n) & 0xffffffff end, rshift=function(a,n) return (a & 0xffffffff)>>n end,
      rrotate=function(a,n) a=a & 0xffffffff return ((a>>n)|(a<<(32-n))) & 0xffffffff end }
    """)
    chunk = lua.eval("function(src, a) return load('local a = ... ; return (function(...) ' .. src .. ' end)(table.unpack(a))', '=installer') end")
    fn = chunk(INSTALLER, to_lua(args))
    fn(to_lua(args))
    return "\n".join(out), events["reboot"]

def main():
    work = Path(tempfile.mkdtemp())
    repo, comp = work / "repo", work / "comp"
    repo.mkdir(); comp.mkdir()
    (repo / "startup_v10.lua").write_text('local VERSION = "10"\nprint("v10")\n')
    (repo / "startup_v21.lua").write_text('local VERSION = "21"\nprint("v21")\n')
    (repo / "startup_v22.lua").write_text('local VERSION = "22"\nprint("v22")\n')
    tag(repo, work, "pv21"); tag(repo, work, "pv22")      # single file releases, no manifest
    write_tree(repo / "os", 23, {"prismarine/data/keepme.txt": "x"})
    r = sh("manifest", "23", "--data-format", "2", cwd=repo); check("manifest v23", r.returncode == 0, r.stderr)
    check("verify v23", sh("verify", cwd=repo).returncode == 0)
    tag(repo, work, "pv23")
    write_tree(repo / "os", 24, {"prismarine/ui/topbar.lua": "return 3\n"}, drop=["prismarine/apps/messenger.lua"])
    r = sh("manifest", "24", "--data-format", "2", cwd=repo); check("manifest v24", r.returncode == 0, r.stderr)
    tag(repo, work, "pv24")
    ENV["drafts"] = ["pv99"]
    ENV["tags"]["pv25"] = ENV["tags"]["pv24"]          # wrong tag: holds the v24 manifest
    (repo / "os/startup.lua").write_text("edited after build\n")
    check("verify catches edits", sh("verify", cwd=repo).returncode != 0)
    (repo / "os/startup.lua").write_text('local VERSION = "24"\nprint("boot")\n')

    (comp / "startup.lua").write_text('local VERSION = "21"\nprint("v21")\n')
    (comp / ".simpleos_settings").write_text("secret")

    out, rb = run_installer(repo, comp, ["99"], keys="")
    check("draft release hidden", "does not exist" in out, out[-200:])
    out, rb = run_installer(repo, comp, ["10"], keys="yn", lines=["", "10"])
    check("main-only single file version installs", 'VERSION = "10"' in (comp / "startup.lua").read_text(), out[-300:])
    (comp / "startup.lua").write_text('local VERSION = "21"\nprint("v21")\n')
    out, rb = run_installer(repo, comp, ["25"], keys="yn", lines=[""])
    check("tag holding wrong manifest rejected", "does not belong" in out, out[-200:])

    out, rb = run_installer(repo, comp, ["23"], keys="yn", lines=[""])
    check("install pv23 over v21", (comp / "prismarine/apps/messenger.lua").exists() and 'VERSION = "23"' in (comp/"startup.lua").read_text(), out[-300:])
    check("v21 startup backed up", (comp / ".prismarine_backup/files/startup.lua").exists())
    check("stage cleaned", not (comp / ".prismarine_stage").exists())
    st = json.loads((comp / ".prismarine_installed.json").read_text()); check("state is 23", st["version"] == 23)
    (comp / "prismarine/data").mkdir(parents=True, exist_ok=True); (comp / "prismarine/data/user.dat").write_text("mine")

    out, rb = run_installer(repo, comp, ["24"], keys="yn", lines=[""])
    check("upgrade pv24 adds file", (comp / "prismarine/ui/topbar.lua").exists(), out[-300:])
    check("upgrade removes orphan", not (comp / "prismarine/apps/messenger.lua").exists())
    check("apps dir pruned", not (comp / "prismarine/apps").exists())
    check("user data kept", (comp / "prismarine/data/user.dat").read_text() == "mine" and (comp / ".simpleos_settings").exists())

    out, rb = run_installer(repo, comp, ["21"], keys="yn", lines=["", "wrong"])
    check("downgrade needs typed version", 'VERSION = "24"' in (comp / "startup.lua").read_text() and "Cancelled" in out, out[-200:])
    out, rb = run_installer(repo, comp, ["21"], keys="yn", lines=["", "21"])
    check("downgrade to release pv21 (single file)", 'VERSION = "21"' in (comp / "startup.lua").read_text(), out[-300:])
    check("downgrade removes release files", not (comp / "prismarine/kernel").exists() and not (comp / "prismarine/ui").exists())
    check("downgrade keeps data", (comp / "prismarine/data/user.dat").read_text() == "mine" and (comp / ".simpleos_settings").read_text() == "secret")
    check("data format drop backs up data", (comp / ".prismarine_backup/data/prismarine/data/user.dat").exists())

    out, rb = run_installer(repo, comp, ["undo"], keys="yn")
    check("undo restores v24", 'VERSION = "24"' in (comp / "startup.lua").read_text() and (comp / "prismarine/ui/topbar.lua").exists(), out[-300:])
    check("undo clears backup", not (comp / ".prismarine_backup").exists())
    check("undo twice says nothing", "nothing to undo" in run_installer(repo, comp, ["undo"], keys="")[0])

    before = (comp / "startup.lua").read_text()
    out, rb = run_installer(repo, comp, ["23"], keys="yn", lines=["", "23"], tamper=("kernel.lua", "return 666\n"))
    check("tampered file aborts", "Hash mismatch" in out and (comp / "startup.lua").read_text() == before and not (comp / ".prismarine_stage").exists(), out[-300:])

    good = hashlib.sha256((ENV["tags"]["pv23"] / "manifest.json").read_bytes()).hexdigest()
    out, rb = run_installer(repo, comp, ["23"], keys="y", lines=["0" * 64, "23"])
    check("wrong manifest hash aborts", "does not match your hash" in out, out[-200:])
    out, rb = run_installer(repo, comp, ["23"], keys="yn", lines=[good, "23"])
    check("right manifest hash installs", 'VERSION = "23"' in (comp / "startup.lua").read_text(), out[-300:])

    ENV["api"] = False
    out, rb = run_installer(repo, comp, ["24"], keys="yn", lines=[""])
    check("API blocked: probing finds pv24", 'VERSION = "24"' in (comp / "startup.lua").read_text(), out[-300:])
    ENV["api"] = True

    bad = json.loads((repo / "manifest.json").read_text())
    bad["files"].append({"path": "../evil.lua", "src": "os/startup.lua", "sha256": "0" * 64, "size": 1})
    (repo / "manifest.json").write_text(json.dumps(bad))
    tag(repo, work, "pv26x"); ENV["tags"]["pv24"] = ENV["tags"].pop("pv26x")
    out, rb = run_installer(repo, comp, ["24"], keys="yn", lines=[""])
    check("path traversal rejected", "bad entry" in out and not (work / "evil.lua").exists(), out[-200:])

    print("\nfailures:", fails)
    shutil.rmtree(work, ignore_errors=True)
    sys.exit(1 if fails else 0)

main()
