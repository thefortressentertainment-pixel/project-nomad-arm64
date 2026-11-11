# Binary assets, stored as base64 blocks

The 22 binary files in this repo (favicons and docs images under
`admin/public/`, the empty Calibre library database, and the two sample
Wikipedia `.zim` files under `install/`) are stored here as base64 text
blocks, 1 MiB of original data per block.

## Why

The push route used to upload this repo to GitHub only accepts UTF-8
text files. Binary files cannot be pushed through it directly, so each
binary was split into 1 MiB blocks and base64-encoded. Base64 is
lossless: decoding the blocks gives back the exact original bytes.

## What is here

- `manifest.json` — one entry per binary file: its original path, size,
  SHA256 hash, and the ordered list of block files that hold it.
- `NNN-<path>.b64` — the base64 blocks, in order. Block names carry the
  original path with `/` as `__` and spaces as `_`.
- `restore-binaries.sh` — rebuilds every binary from its blocks and
  verifies it against the manifest.

## Restoring

From the repository root:

```sh
sh binary-blocks/restore-binaries.sh
```

The script writes each file back to its original path and checks its
SHA256. It stops with an error if any file does not match.

The two files `admin/public/favicon-512x512.png` and
`admin/public/favicon-512x512 - Copy.png` are identical in the upstream
tree; both are preserved here as separate entries.

The `.zim` files are sample Wikipedia data shipped with upstream, not
code. They are preserved for completeness, not required to run NOMAD.
