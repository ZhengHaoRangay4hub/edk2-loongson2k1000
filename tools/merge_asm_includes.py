#!/usr/bin/env python3
"""Inline cross-file #include of .S files into a single assembly source.

EDK2's Trim tool drops every line that does not belong to the top-level
source file, so PMON-style `#include "other.S"` assembly aggregation is
silently discarded by the normal EDK2 build. Merging the files textually
before the build keeps the single-translation-unit structure PMON relies
on (shared local labels, mid-stream state).

Headers pulled in by inlined files are rewritten to paths relative to the
top-level file so the C preprocessor still finds them. Files that do not
exist are skipped with a comment (leftovers from the PMON tree that this
port does not carry).
"""
import os
import re
import sys

inc_re = re.compile(r'^(\s*)#include\s+"([^"]+)"\s*$')


def merge(path, topdir, seen):
    out = []
    base = os.path.dirname(path)
    with open(path) as f:
        for line in f:
            m = inc_re.match(line)
            if m:
                inc = os.path.normpath(os.path.join(base, m.group(2)))
                rel = os.path.relpath(inc, topdir)
                if os.path.exists(inc) and inc.endswith('.S'):
                    out.append('/* ---- begin %s (inlined for EDK2 Trim) ---- */\n' % m.group(2))
                    out.append(merge(inc, topdir, seen))
                    out.append('/* ---- end %s ---- */\n' % m.group(2))
                elif os.path.exists(inc):
                    # header: keep as a cpp include, but reachable from topdir
                    out.append('%s#include "%s"\n' % (m.group(1), rel))
                else:
                    out.append('/* skipped missing include %s */\n' % m.group(2))
            else:
                out.append(line)
    return ''.join(out)


def main():
    target = os.path.abspath(sys.argv[1])
    sys.stdout.write(merge(target, os.path.dirname(target), set()))


if __name__ == '__main__':
    main()
