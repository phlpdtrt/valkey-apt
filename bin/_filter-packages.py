#!/usr/bin/env python3
"""Filter a dpkg-scanpackages output down to the stanzas whose Filename is
listed in allowed_paths_file. Helper for publish-repo.sh - dpkg-scanpackages
always scans the whole shared pool, but each dists/<codename>/main/binary-<arch>
slot must only advertise the .debs belonging to that codename+arch.
"""
import sys
import os

def main():
    packages_file, allowed_paths_file, repo_dir = sys.argv[1:4]

    with open(allowed_paths_file) as f:
        allowed = {os.path.abspath(line.strip()) for line in f if line.strip()}

    with open(packages_file) as f:
        raw = f.read()

    stanzas = [s for s in raw.split("\n\n") if s.strip()]
    kept = []
    for stanza in stanzas:
        filename = None
        for line in stanza.splitlines():
            if line.startswith("Filename:"):
                filename = line.split(":", 1)[1].strip()
                break
        if filename is None:
            continue
        abs_path = os.path.abspath(os.path.join(repo_dir, filename))
        if abs_path in allowed:
            kept.append(stanza)

    sys.stdout.write("\n\n".join(kept))
    if kept:
        sys.stdout.write("\n")

if __name__ == "__main__":
    main()
