# Changelog — Project NOMAD ARM64 Port

> **Built with agentic AI:** This port was created with the help of agentic AI (an AI coding assistant working alongside the maintainer). The code, docs, and release notes were produced collaboratively by a human and an AI agent.

## v1.35.1-arm64 — 2026-11-13

### Added
- ARM64 support: installer accepts `aarch64`/`arm64` (was x86-64 only).
- Multi-arch Docker images (`linux/amd64`, `linux/arm64`) for the admin image and both sidecars, published to the fork's own GHCR namespace.
- Four content editions with baked-in ZIMs: `:lite`, `:standard`, `:comms`, `:full` (plus versioned tags, e.g. `1.35.1-standard`).
- Easy installer (`install.sh`): edition picker, free-disk check, GHCR availability check, honours `NOMAD_SOURCE_REPO` / `NOMAD_SOURCE_BRANCH` / `NOMAD_VARIANT`.
- Plain-language install guide (`INSTALL-EASY.md`) and ARM runbook (`README-ARM.md`), including the Termux/QEMU phone path.
- Fork-aware installer: rewrites NOMAD image references to the source repo's GHCR namespace; warns on ARM if still pointed at upstream.
- `install.sh` bootstrap downloads and runs the full installer with the fork's repo/branch/variant.

### Changed
- `setup_nvidia_container_toolkit()` returns immediately on ARM (no NVIDIA GPU; Ollama runs CPU-only).
- In-UI updater image-tag rewrite now matches any GHCR owner (was hardcoded to upstream).
- Admin `/settings` root route redirects to `/settings/system`; static public files included in the image.

### Removed / disabled on ARM
- Translate service: amd64-only (Bergamot/intgemm is x86-specific); its workflow stays pinned to `linux/amd64`. Do not install `nomad_translate` on ARM.
- Excalidraw: amd64-only image; do not install on ARM.

### Fixed
- Admin/public static images (favicons, banners, docs images, creator-packs images) now included in the image build; missing files fail the build instead of shipping broken.
- Easy-setup footer wrapping on mobile.
- Nested `${{ }}` in `:latest` image tags (CI).
- Binary assets (Calibre `metadata.db` etc.) restored from tracked base64 chunks before the primary build.

### Known issues
- Translate container crash-loops with `exec format error` on ARM (expected; it is amd64-only).
- Excalidraw has no ARM64 image.
- Ollama is CPU-only on ARM; large models are slow and memory-hungry — start small.
- The phone path (Termux/QEMU, TCG emulation) is 10–25× slower than native; first boot takes 20–30 minutes; keep the phone plugged in and use `termux-wake-lock`.
