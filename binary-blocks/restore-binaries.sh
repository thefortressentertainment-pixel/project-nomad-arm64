#!/bin/sh
# Restore the binary assets of project-nomad from their base64 blocks.
#
# The 22 binary files (favicons, docs images, the empty Calibre library
# database and the two sample Wikipedia .zim files) are stored in this
# directory as base64 text blocks because the GitHub push route used for
# this repo only accepts UTF-8 text. Base64 is lossless, so the restored
# files are byte-for-byte identical to the originals.
#
# Usage (from the repository root):
#   sh binary-blocks/restore-binaries.sh
#
# The script verifies every restored file against its SHA256 in
# manifest.json and stops with an error if any file does not match.
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
import base64, hashlib, json, os, sys

with open('binary-blocks/manifest.json') as f:
    manifest = json.load(f)

ok = 0
for entry in manifest['files']:
    parts = []
    for chunk in entry['chunks']:
        with open(os.path.join('binary-blocks', chunk)) as f:
            parts.append(base64.b64decode(f.read()))
    data = b''.join(parts)
    if len(data) != entry['size']:
        sys.exit(f"size mismatch for {entry['path']}: "
                 f"got {len(data)}, expected {entry['size']}")
    sha = hashlib.sha256(data).hexdigest()
    if sha != entry['sha256']:
        sys.exit(f"sha256 mismatch for {entry['path']}")
    os.makedirs(os.path.dirname(entry['path']) or '.', exist_ok=True)
    with open(entry['path'], 'wb') as f:
        f.write(data)
    ok += 1
    print(f"restored {entry['path']} ({entry['size']} bytes, sha256 OK)")
print(f"restored {ok} binary files, all SHA256 checks passed")
PY
