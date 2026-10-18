#!/usr/bin/env python3
"""
prismarine_share.py  -  PC helper for the Prismarine OS Import app.

  python prismarine_share.py serve <folder> [--port 8000] [--lan] [--no-hash]
      Shares the files in <folder> (not sub folders) so the Import app can
      download them over HTTP in ranged chunks. Any size works.

  python prismarine_share.py split <file> [--size KB] [--out DIR]
      Cuts a file into name.part1, name.part2, ... for drag and drop when the
      game refuses large drops. The parts are written next to the file, not in
      a folder, unless you pass --out. Default part size is 400 KB.

  python prismarine_share.py join <first part> [--out FILE]
      Joins parts back together on the PC (for checking a split).

Needs Python 3.8 or newer. No extra packages.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BLOCK = 1024 * 1024


# --------------------------------------------------------------------------
# split and join
# --------------------------------------------------------------------------

def cmd_split(args):
    src = os.path.abspath(args.file)
    if not os.path.isfile(src):
        sys.exit("No such file: " + src)
    part_size = max(1, int(args.size * 1024))
    out_dir = os.path.abspath(args.out) if args.out else os.path.dirname(src)
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.basename(src)
    total = os.path.getsize(src)
    if total == 0:
        sys.exit("That file is empty.")
    count = 0
    with open(src, "rb") as f:
        while True:
            data = f.read(part_size)
            if not data:
                break
            count += 1
            path = os.path.join(out_dir, "%s.part%d" % (base, count))
            with open(path, "wb") as out:
                out.write(data)
    print("Split %s (%d bytes) into %d parts of up to %d KB." % (base, total, count, part_size // 1024))
    print("Parts are in: " + out_dir)
    print("Drop every %s.partN file onto the Import > Drop files screen, then open Join split parts." % base)


def cmd_join(args):
    first = os.path.abspath(args.part)
    m = re.match(r"^(.*)\.part(\d+)$", os.path.basename(first))
    if not m:
        sys.exit("Give the name of one part, like song.dfpwm.part1")
    base = m.group(1)
    folder = os.path.dirname(first)
    out_path = os.path.abspath(args.out) if args.out else os.path.join(folder, base)
    n = 1
    with open(out_path, "wb") as out:
        while True:
            p = os.path.join(folder, "%s.part%d" % (base, n))
            if not os.path.isfile(p):
                break
            with open(p, "rb") as f:
                while True:
                    block = f.read(BLOCK)
                    if not block:
                        break
                    out.write(block)
            n += 1
    if n == 1:
        os.remove(out_path)
        sys.exit("Part 1 was not found.")
    print("Joined %d parts into %s" % (n - 1, out_path))


# --------------------------------------------------------------------------
# serve
# --------------------------------------------------------------------------

class Share:
    def __init__(self, folder, hashing):
        self.folder = folder
        self.hashing = hashing
        self.cache = {}  # name -> (mtime_ns, size, sha256)
        self.lock = threading.Lock()

    def names(self):
        out = []
        for n in sorted(os.listdir(self.folder), key=str.lower):
            if n.startswith("."):
                continue
            if os.path.isfile(os.path.join(self.folder, n)):
                out.append(n)
        return out

    def path(self, name):
        # Only plain files that sit directly in the shared folder.
        if not name or name != os.path.basename(name) or name.startswith("."):
            return None
        p = os.path.join(self.folder, name)
        return p if os.path.isfile(p) else None

    def sha(self, name):
        if not self.hashing:
            return None
        p = os.path.join(self.folder, name)
        st = os.stat(p)
        with self.lock:
            hit = self.cache.get(name)
            if hit and hit[0] == st.st_mtime_ns and hit[1] == st.st_size:
                return hit[2]
        h = hashlib.sha256()
        with open(p, "rb") as f:
            while True:
                block = f.read(BLOCK)
                if not block:
                    break
                h.update(block)
        digest = h.hexdigest()
        with self.lock:
            self.cache[name] = (st.st_mtime_ns, st.st_size, digest)
        return digest

    def listing(self):
        files = []
        for n in self.names():
            entry = {"name": n, "size": os.path.getsize(os.path.join(self.folder, n))}
            digest = self.sha(n)
            if digest:
                entry["sha256"] = digest
            files.append(entry)
        return {"files": files}


def make_handler(share):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        server_version = "prismarine_share"

        def log_message(self, fmt, *a):
            sys.stderr.write("%s  %s\n" % (self.address_string(), fmt % a))

        def _send(self, code, body=b"", ctype="text/plain", extra=None):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def _route(self):
            url = urllib.parse.urlparse(self.path)
            q = urllib.parse.parse_qs(url.query)
            if url.path == "/list":
                body = json.dumps(share.listing()).encode()
                return self._send(200, body, "application/json")
            if url.path == "/file":
                name = (q.get("name") or [""])[0]
                p = share.path(name)
                if not p:
                    return self._send(404, b"not found")
                return self._file(p)
            if url.path in ("/", "/ping"):
                return self._send(200, b"prismarine_share ok")
            return self._send(404, b"not found")

        def _file(self, p):
            size = os.path.getsize(p)
            start, end, code = 0, size - 1, 200
            rng = self.headers.get("Range")
            if rng:
                m = re.match(r"^bytes=(\d*)-(\d*)$", rng.strip())
                if not m or (m.group(1) == "" and m.group(2) == ""):
                    return self._send(416, b"bad range", extra={"Content-Range": "bytes */%d" % size})
                if m.group(1) == "":
                    n = int(m.group(2))
                    start, end = max(0, size - n), size - 1
                else:
                    start = int(m.group(1))
                    end = int(m.group(2)) if m.group(2) else size - 1
                    end = min(end, size - 1)
                if start >= size or start > end:
                    return self._send(416, b"range not satisfiable", extra={"Content-Range": "bytes */%d" % size})
                code = 206
            length = end - start + 1
            self.send_response(code)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(length))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Cache-Control", "no-store")
            if code == 206:
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
            self.end_headers()
            if self.command == "HEAD":
                return
            with open(p, "rb") as f:
                f.seek(start)
                left = length
                while left > 0:
                    block = f.read(min(BLOCK, left))
                    if not block:
                        break
                    self.wfile.write(block)
                    left -= len(block)

        def do_GET(self):
            try:
                self._route()
            except (BrokenPipeError, ConnectionResetError):
                pass

        do_HEAD = do_GET


    return Handler


def lan_address():
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def cmd_serve(args):
    folder = os.path.abspath(args.folder)
    if not os.path.isdir(folder):
        sys.exit("No such folder: " + folder)
    share = Share(folder, not args.no_hash)
    bind = "0.0.0.0" if args.lan else "127.0.0.1"
    try:
        server = ThreadingHTTPServer((bind, args.port), make_handler(share))
    except OSError as e:
        sys.exit("Cannot start on port %d: %s" % (args.port, e))
    shown = lan_address() if args.lan else "127.0.0.1"
    names = share.names()
    print("Sharing %d file(s) from %s" % (len(names), folder))
    print("In Prismarine open Import > Import settings > PC address and enter:")
    print("    %s:%d" % (shown if args.lan else "localhost", args.port))
    print("The server's computercraft-server.toml must allow this address (see Setup help).")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


def main():
    ap = argparse.ArgumentParser(description="PC helper for the Prismarine OS Import app.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("serve", help="share a folder over HTTP")
    s.add_argument("folder")
    s.add_argument("--port", type=int, default=8000)
    s.add_argument("--lan", action="store_true", help="listen on your network, not only this PC")
    s.add_argument("--no-hash", action="store_true", help="skip SHA-256 (faster listing of huge files)")
    s.set_defaults(fn=cmd_serve)

    p = sub.add_parser("split", help="cut a file into .partN pieces")
    p.add_argument("file")
    p.add_argument("--size", type=float, default=400, help="part size in KB (default 400)")
    p.add_argument("--out", help="write parts here instead of next to the file")
    p.set_defaults(fn=cmd_split)

    j = sub.add_parser("join", help="join .partN pieces on the PC")
    j.add_argument("part", help="any part, such as song.dfpwm.part1")
    j.add_argument("--out")
    j.set_defaults(fn=cmd_join)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
