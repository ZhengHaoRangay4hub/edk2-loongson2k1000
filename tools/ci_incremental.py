#!/usr/bin/env python3
"""Make a restored EDK2 Build tree usable as an incremental build cache.

`actions/cache` restores files with the mtimes they had when the cache was
created, while a fresh checkout stamps every source with the current time.
Make would therefore see "all sources newer than all objects" and rebuild
everything, which defeats the cache.

This helper compares every source file against a manifest saved next to the
build tree and normalises mtimes so that make's timestamp rules match the
content:

  * file content unchanged  -> mtime set to an old fixed time (older than
                               the restored objects, so it is not rebuilt)
  * file new or changed     -> mtime set to now (rebuilt, and everything
                               that depends on it)

Usage: ci_incremental.py <source-root> <manifest-path>
"""
import hashlib
import json
import os
import sys
import time

SKIP_DIRS = {'Build', '.git'}
OLD_TS = time.mktime((2020, 1, 1, 0, 0, 0, 0, 0, -1))


def file_hash(path):
    digest = hashlib.sha256()
    try:
        with open(path, 'rb') as handle:
            for chunk in iter(lambda: handle.read(1 << 20), b''):
                digest.update(chunk)
    except OSError:
        return None
    return digest.hexdigest()


def main():
    root = os.path.abspath(sys.argv[1])
    manifest_path = os.path.abspath(sys.argv[2])

    old = {}
    if os.path.exists(manifest_path):
        try:
            old = json.load(open(manifest_path))
        except ValueError:
            old = {}

    now = {}
    changed = 0
    unchanged = 0

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = os.path.join(dirpath, name)
            digest = file_hash(path)
            if digest is None:
                continue
            rel = os.path.relpath(path, root)
            now[rel] = digest
            if old.get(rel) == digest:
                unchanged += 1
                os.utime(path, (OLD_TS, OLD_TS))
            else:
                changed += 1
                os.utime(path)

    os.makedirs(os.path.dirname(manifest_path), exist_ok=True)
    with open(manifest_path, 'w') as handle:
        json.dump(now, handle)

    print(
        'incremental: %d file(s) changed or new, %d unchanged '
        '(mtimes normalised against %d cached entries)'
        % (changed, unchanged, len(old))
    )


if __name__ == '__main__':
    main()
