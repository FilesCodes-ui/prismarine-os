#!/usr/bin/env python3
"""Sign manifest.txt with your release key. Run inside the release/ folder AFTER make_manifest.py.

  python3 tools/sign_manifest.py release.key      sign with your key file
  python3 tools/sign_manifest.py --newkey         make a NEW key (see warning)

release.key holds your 32-byte secret seed as 64 hex characters.
Never upload release.key to GitHub. Keep it on your own computer only.
Needs:  pip install cryptography
"""
import re, sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization as ser

def pub_hex(sk):
    return sk.public_key().public_bytes(ser.Encoding.Raw, ser.PublicFormat.Raw).hex()

def seed_hex(sk):
    return sk.private_bytes(ser.Encoding.Raw, ser.PrivateFormat.Raw, ser.NoEncryption()).hex()

if len(sys.argv) > 1 and sys.argv[1] == "--newkey":
    sk = Ed25519PrivateKey.generate()
    open("release.key", "w").write(seed_hex(sk) + "\n")
    print("Wrote release.key (keep it secret, do not upload it).")
    print("New public key:", pub_hex(sk))
    print("Put it in prismarine/sys/update.lua as RELEASE_KEY, rerun make_manifest.py, then sign.")
    print("WARNING: computers still running the old update.lua will reject this key's signatures,")
    print("so they must be reinstalled with setup.lua once.")
    sys.exit(0)

if len(sys.argv) < 2:
    sys.exit(__doc__)
seed = bytes.fromhex(open(sys.argv[1]).read().strip())
sk = Ed25519PrivateKey.from_private_bytes(seed)
want = re.search(r'RELEASE_KEY = "([0-9a-f]{64})"', open("prismarine/sys/update.lua").read()).group(1)
if pub_hex(sk) != want:
    sys.exit("This key does not match RELEASE_KEY in update.lua. Computers would reject the signature.")
sig = sk.sign(open("manifest.txt", "rb").read()).hex()
open("manifest.sig", "w").write(sig + "\n")
print("manifest.sig written (%d hex chars). Upload it with manifest.txt." % len(sig))
