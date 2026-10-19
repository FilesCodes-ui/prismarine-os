# Prismarine OS releases

A version is a GitHub release with a tag named pv<number>: pv21, pv23, pv24.
The installer lists the releases, then downloads that version's files from its tag.

## Repo layout (main branch)

```
README.md
LICENSE
startup_v3.lua ... startup_v22.lua   frozen, never edit or move
p.shell_v1.lua, p.shell_v2.lua       frozen, v21 fetches these from the root
official_downloads.lua               frozen, v21 fetches this from the root
manifest.json                        generated, belongs to the newest version
os/                                  the OS as it sits on the computer
  startup.lua
  prismarine/kernel/ ...
installer/installer_v2.lua           the pastebin installer
tools/                               build_release.py, test_installer.py
docs/                                whitepaper, design notes, this file
assets/                              atlas.lua, prismarine_share.py, audio
```

main holds the work in progress. Old versions live in their tags, so the root
stops growing.

## Why the old files stay

v21 reads the root of main through the GitHub API and downloads
`startup_v<N>.lua`, `p.shell_v<N>.lua` and `official_downloads.lua` from
`raw.githubusercontent.com/<repo>/main/`. Moving them breaks every installed
v21 and v22. v21 and v22 never see v23 or later. Those computers move up by
running the installer once.

## Moves that are safe now

v21 does not mention `atlas.lua`, `prismarine_share.py` or the `.dfpwm` file.
Search `p.shell_v2.lua`, `official_downloads.lua`, the p.audio files and v22 for
those names first. If none match, move them to `assets/`.
`p.audio_v*` and `p_archive_v*` are not fetched by v21. Check v22 before moving.

## Publishing a version

1. Put the OS files in `os/`.
2. From the repo root run
   `python tools/build_release.py manifest 23 --data-format 2`
   It writes `manifest.json` and prints the manifest SHA-256. Publish that hash
   somewhere an attacker cannot edit.
3. Run `python tools/build_release.py verify`.
4. Commit `os/` and `manifest.json` together.
5. On GitHub: Releases, Draft a new release, create the tag `pv23` on that
   commit, publish.

Never move a tag after publishing. To fix a bug, publish the next number.
The installer checks that the manifest inside a tag says the same version as the tag.

## Single file versions

A release with no `manifest.json` is a single file version. The installer
downloads `startup_v<N>.lua` from that tag. To give an old version a release,
tag the commit that holds the file. Single file versions in the root of main
with no release still show in the list.

## Installing, upgrading, downgrading

Installer actions: pick a version, `latest`, a number, or `undo`.
Every install follows the same steps.

1. List the releases through the GitHub API. If the API is blocked or rate
   limited, check pv1 to pv40 one at a time.
2. Download every file into `/.prismarine_stage`. Check each SHA-256 and
   syntax-check each Lua file. Any failure deletes the stage and changes nothing.
3. Copy every file about to be replaced or removed into `/.prismarine_backup`.
4. Move the files into place. `startup.lua` goes last, so a crash halfway
   still boots the old version.
5. Delete files the old version owned and the new one does not.
   Only paths in the old install record are ever deleted.
6. Write `/.prismarine_installed.json`, the install record.

Downgrades add a warning and require typing the version number.
If the older version reads an older data format, the data folders go into the
backup first. Paths in the manifest `keep` list are never deleted: settings,
secure boot data and `prismarine/data/`.

`undo` restores the backup, removes files the install created, and restores the
old install record. It works offline.

## Safety rules

Every manifest path is checked. No absolute paths, no `..`, nothing in the
installer's own folders or in `rom/`. One bad entry rejects the whole manifest.
The repo serves both the manifest and the files, so only the hash you type from a
separate source protects you from a compromised repo.

## Known limits

GitHub's API allows 60 requests per hour per IP address without a key. A busy
server falls back to probing, which is slower.
Secure boot stores a hash of `startup.lua`. An install changes that file.
Re-enroll after installing.
A computer that never ran an install record has no list of files the old version
owned. The first install over it removes nothing.
