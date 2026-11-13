# Project NOMAD — ARM64 Port

Branch: `main` — an unofficial ARM64 port of
[Crosstalk-Solutions/project-nomad](https://github.com/Crosstalk-Solutions/project-nomad)
v1.35.1, prepared by Jethro for Matthew.

Upstream officially supports x86-64 only (see `install/install_nomad.sh`,
PR #419). This branch does not change that upstream claim — it makes the
port buildable and installable on ARM64 Linux.

## What this branch changes

1. **`install/install_nomad.sh`**
   - `check_is_x86_64()` → `check_architecture()`, accepting
     `x86_64`/`amd64` and `aarch64`/`arm64`.
   - `setup_nvidia_container_toolkit()` returns immediately on ARM —
     no NVIDIA GPU on ARM Linux, Ollama runs CPU-only.

2. **`.github/workflows/build-primary-image.yml`,
   `build-disk-collector.yml`, `build-sidecar-updater.yml`**
   - Added QEMU + Buildx setup and `platforms: linux/amd64,linux/arm64`
     so the admin image and both sidecars publish multi-arch manifests.
   - Tags now use `ghcr.io/${{ github.repository }}` instead of the
     hardcoded `ghcr.io/crosstalk-solutions/...`, so a fork publishes
     its own images to its own GHCR namespace. (Before this fix, a
     fork's CI could not publish at all — it has no write access to
     the upstream org's packages.)
   - The main `Dockerfile` already handled `TARGETARCH` for go-pmtiles,
     with separate AMD64 and ARM64 SHA256 pins — no change needed there.

3. **`install/install_nomad.sh` — fork-aware source**
   - The installer used to fetch the compose file and helper scripts
     from upstream `main`, and that compose file pulls the amd64-only
     `ghcr.io/crosstalk-solutions/project-nomad:latest`. On ARM that
     would have failed at `docker compose up` even with this branch.
   - It now honours `NOMAD_SOURCE_REPO` / `NOMAD_SOURCE_BRANCH`
     (defaults: the fork `thefortressentertainment-pixel/project-nomad-arm64`
     / `main`) for those downloads, rewrites the
     three NOMAD images in the downloaded compose file to the source
     repo's owner, and warns on ARM if it is still pointed at
     upstream. Setting the variables is only needed to point at a
     different repo/branch (see below).

4. **`install/sidecar-updater/update-watcher.sh`**
   - The in-UI updater's image-tag rewrite hardcoded the upstream
     GHCR owner, so it would silently no-op on a fork install. It now
     matches any GHCR owner (`ghcr.io/<owner>/project-nomad`).

5. **Translate service — disabled on ARM**
   - `install/nomad-translate/Dockerfile` is explicitly amd64-only:
     Bergamot's intgemm backend is x86-specific and there is no
     aarch64 wheel. Its workflow stays pinned to `linux/amd64`.
   - Do not install `nomad_translate` on ARM. A future replacement
     would need Marian's `ruy` path or Mozilla Translations.

## What should work on ARM64

From the catalog in `admin/database/seeders/service_seeder.ts`:

| Service | Image | ARM64 |
|---|---|---|
| Admin / Command Center | `ghcr.io/<fork-owner>/project-nomad` (rebuilt multi-arch by this branch's CI) | Yes — rebuilt multi-arch |
| MySQL | `mysql:8.0` | Yes |
| Redis | `redis:7-alpine` | Yes |
| Dozzle | `amir20/dozzle:v10.0` | Yes |
| Kiwix | `ghcr.io/kiwix/kiwix-serve:3.8.1` | Yes |
| Qdrant | `qdrant/qdrant:v1.16` | Yes |
| Ollama | `ollama/ollama:0.33.3` | Yes, CPU-only |
| Kolibri Gen 2 | `learningequality/kolibri:0.19.4` | Yes (Python) |
| CyberChef | `ghcr.io/gchq/cyberchef:10.24.0` | Yes |
| FlatNotes, FileBrowser, Calibre-Web, Stirling PDF, IT Tools, Homebox, Vaultwarden, Jellyfin, Meshtastic/MeshCore web | various | Yes — all verified arm64, including all GHCR images (see Verification) |

**Excalidraw is amd64-only** (`excalidraw/excalidraw:sha-4bfc5bb`) — do not install on ARM.

The admin code already maps `aarch64` → `arm64` in
`system_controller.ts`, `check_service_updates_job.ts`, and
`app_auto_update_service.ts`, so update checks should resolve the
right architecture.

## What will NOT work

- **Running on an Android phone directly.** Android has no Docker
  daemon, no Debian, and no `/opt/project-nomad`. An ARM port runs on
  ARM *Linux* — Raspberry Pi 5 (Pi OS / Debian), an ARM server, or an
  ARM VM on the phone (see "Running on the phone via a QEMU VM"
  below). Use the phone to edit and manage it (VSCodroid, browser
  to `http://<host>:8080`), or to host the VM — not to run Docker
  natively.
- **Translate** — see above.
- **GPU AI** — no NVIDIA / ROCm on ARM. Ollama CPU-only, so use
  small models and expect it to be slow. The README's optimal specs
  (32 GB RAM, RTX 3060) do not apply.
- **Jellyfin transcoding / heavy AI** on a Pi 5 — likely too slow
  for practical use; core library / notes / maps should be fine.
- **Alpine Linux as the VM/host OS.** The installer requires
  Debian (`/etc/debian_version`, `apt-get`, `systemd`). An Alpine
  VM would fail the Debian check immediately — use Debian 12, not
  Alpine, despite Alpine being the lighter VM choice.

## Target hardware (tested target)

- Raspberry Pi 5, 8 GB, Pi OS (Debian-based), Docker + Docker Compose
  v2, 5 GB free for the base install, 10 GB comfortable, more for
  content. AI adds ~25 GB if you install Ollama models.
- The phone install is verified live — see Verification.

## Install on ARM Linux

### 0. Publish the fork's multi-arch images first

The installer pulls `:latest` for the admin, updater and
disk-collector images. Those only exist for ARM once the fork's CI
has built them — upstream's are amd64-only.

1. In the fork, go to Settings → Secrets and variables → Actions and
   add your GitHub username to the `DEPLOYMENT_AUTHORIZED_USERS`
   secret (the workflows refuse to build for anyone not listed
   there — with no secret set, the build job is silently skipped).
2. In Actions, run each workflow from the `main` branch, with
   a version (e.g. `1.35.1`) and **tag_latest checked**:
   `Build Primary Docker Image`, `Build Disk Collector Image`,
   `Build Sidecar Updater Image`. They publish to
   `ghcr.io/thefortressentertainment-pixel/project-nomad-arm64:latest` (and the two sidecars).
   Make the three packages public in the fork if the VM's Docker
   pull needs to reach them without credentials. To publish the
   content editions (`:lite`, `:standard`, `:comms`, `:full`), also run
   `Build Variant Docker Images` with the same version.
3. Then install, pointing the installer at the fork:

```bash
# On the ARM Linux host (Pi 5, etc.), Debian-based only:
sudo apt-get update && sudo apt-get install -y curl
curl -fsSL https://raw.githubusercontent.com/thefortressentertainment-pixel/project-nomad-arm64/main/install/install_nomad.sh -o install_nomad.sh
export NOMAD_SOURCE_REPO=thefortressentertainment-pixel/project-nomad-arm64 NOMAD_SOURCE_BRANCH=main
sudo -E bash install_nomad.sh
# Open http://localhost:8080 or http://<host-ip>:8080
```

The installer defaults to the fork (`thefortressentertainment-pixel/project-nomad-arm64` / `main`), so the `export` above is only needed if you are pointing at a different repo or branch. `sudo -E` matters: plain
`sudo` drops the two variables and the installer silently falls back
to upstream (it will warn on ARM, but only after downloading).
The installer still requires Debian, sudo, and Docker — it installs
Docker itself if missing.

## Content editions (image variants)

The plain `:latest` image ships no offline content — everything is
downloaded later from inside NOMAD. The variant images bake a ZIM set
into the image so a fresh install already has a library, with no
separate download step. The app is identical in every edition; only
the bundled content differs.

| Tag | Bundled ZIMs | Content | Needs at least |
|---|---|---|---|
| `:lite` | `wikipedia_en_100_mini_2026-01.zim` | ~4 MB | 5 GB free |
| `:standard` | `wikipedia_en_top_mini_2026-06.zim`, `wwwnc.cdc.gov_en_all_2024-11.zim`, `zimgit-medicine_en_2024-08.zim` | ~580 MB | 6 GB free |
| `:comms` | `wikipedia_en_100_mini_2026-01.zim`, `ham.stackexchange.com_en_all_2026-10.zim` | ~80 MB | 5 GB free |
| `:full` | All of the above, plus `irp.fas.org_en_military-medicine_2026-10.zim`, `nhs.uk_en_medicines_2025-12.zim` | ~740 MB | 7 GB free |

How it works:

- The `Dockerfile` has one `zim-content` stage that downloads the ZIMs
  from the same `download.kiwix.org` URLs the Content Manager uses at
  runtime (see `collections/wikipedia.json` and
  `collections/kiwix-categories.json`), each SHA256-verified, and one
  `variant-<name>` stage per edition that copies only its ZIMs into
  `/app/bundled-zim`. A bare `docker build` still produces the plain
  image (the final `release` stage is the production image with no
  bundled ZIMs) — variants are built with
  `docker build --target variant-<name>`.
- `/app/storage` is a bind mount at runtime, so ZIMs baked there would
  be shadowed by the mount. Instead the entrypoint
  (`install/entrypoint.sh`) copies bundled ZIMs into `/app/storage/zim`
  on first boot, never overwriting files already there. The admin
  rebuilds the Kiwix library XML from the ZIMs on disk at boot if it is
  missing, so seeded files are picked up automatically.
- The `comms` edition additionally pre-pulls the Meshtastic Web
  (`ghcr.io/meshtastic/web:2.7.1`) and MeshCore Web
  (`ghcr.io/axistem-dev/meshcore-web:v1.45.0`) images at install time,
  so those apps install instantly from the dashboard. The apps
  themselves are not baked into the admin image — they are separate
  containers the admin runs on demand.
- The installer (`install.sh`) asks which edition to install
  (default `standard`), checks free disk space against the table above,
  and checks GHCR for that tag before starting. Non-interactive:
  `NOMAD_VARIANT=full bash install.sh`. The chosen edition is recorded
  in `/opt/project-nomad/.nomad-variant`.
- Publish the editions with the **Build Variant Docker Images**
  workflow (`.github/workflows/build-variants.yml`), which pushes
  `:<edition>` and `:<version>-<edition>` for all four editions. The
  plain `:latest` image is built by the existing Build Primary Docker
  Image workflow and is untouched by the variants workflow.

Notes and limits:

- An edition is an install-time choice. Once the ZIMs are seeded into
  `/opt/project-nomad/storage/zim` they live in the host storage volume
  and survive updates. The in-UI updater moves the admin image tag to
  the latest version tag (its existing behaviour) — that does not remove
  seeded content, but a later fresh install with `:latest` would not
  re-seed it; reinstall with the same edition tag to get the bundled
  content back.
- The Translate service is not in any edition: it is broken on ARM
  (amd64-only) and disabled in this port.

## Running on the phone via a QEMU VM

No native Docker on Android, so the phone path is a real Debian 12
VM in Termux under QEMU — the only no-root route that gives a real
`dockerd` + `systemd`, which the installer needs. Based on
[sulthonzh's Debian-on-Android QEMU guide](https://dev.to/sulthonzh/run-real-docker-on-android-no-root-no-tricks-just-qemu-15jn)
(Debian 12, TCG software emulation, first boot 20–30 min, 10–25×
slower than native). Adapted here for this phone — 8 GB RAM /
128 GB storage — and for NOMAD's port 8080.

Check the built-in Linux Terminal first (Settings → System →
Developer options → Linux development environment): if it exists,
use it instead — it is a real Debian VM and skips all of this.
If it is absent, the QEMU route is:

```bash
# In Termux — install from F-Droid, NOT the Play Store (frozen 2020 build).
pkg update -y && pkg upgrade -y
pkg install -y qemu-system-aarch64 openssh curl wget genisoimage
termux-wake-lock   # critical: without it Android kills QEMU minutes after the screen goes dark

mkdir -p ~/qemu-vm && cd ~/qemu-vm
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2
qemu-img resize debian-12-genericcloud-arm64.qcow2 32G   # NOMAD base is ~5 GB + images + content; qcow2 only uses what it needs
```

Build a cloud-init seed (`user-data` with your SSH key and a user
with sudo, plus `meta-data` with `instance-id` / `local-hostname`),
then `genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data`.
Copy the UEFI vars once: `cp $PREFIX/share/qemu/edk2-aarch64-vars.fd ~/qemu-vm/edk2-vars.fd && truncate -s 64M ~/qemu-vm/edk2-vars.fd`.

Boot it (sized for 8 GB RAM — 4 GB / 4 vCPU for the VM, leaving the
rest for Android; NOMAD's port forwarded, not port 80):

```bash
setsid qemu-system-aarch64 \
  -machine virt,gic-version=3 -cpu max,aarch64=on,pmu=on \
  -smp 4 -m 4096 -accel tcg,thread=multi,tb-size=512 \
  -drive if=pflash,format=raw,readonly=on,file=$PREFIX/share/qemu/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file=$HOME/qemu-vm/edk2-vars.fd \
  -drive file=$HOME/qemu-vm/debian-12-genericcloud-arm64.qcow2,if=virtio,format=qcow2,cache=writeback \
  -drive file=$HOME/qemu-vm/seed.iso,if=virtio,format=raw,readonly=on \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:8080 \
  -device virtio-net-pci,netdev=net0 -device virtio-rng-pci \
  -display none -serial file:$HOME/qemu-vm/debian-boot.log > $HOME/qemu-vm/qemu.log 2>&1 &
```

Wait 20–30 min for first boot, then `ssh -p 2222 <user>@<phone-ip>`.
Inside the VM, install Docker (Debian's `docker.io` + Compose v2,
or let the NOMAD installer do it), set Docker's
`max-concurrent-downloads: 1` in `/etc/docker/daemon.json` (TCG is
too slow for parallel pulls — they time out), then run the fork
install from step 0 above, with `NOMAD_SOURCE_REPO` /
`NOMAD_SOURCE_BRANCH` set. Open NOMAD at
`http://<phone-ip>:8080` from the phone's browser.

Expectations, honestly: core NOMAD (Kiwix, Kolibri, notes, maps)
should work, slowly. Skip Ollama models at first — CPU-only AI
under TCG emulation will be very slow and memory-hungry on 4 GB.
Keep the phone plugged in; Android may still kill Termux in the
background, and `termux-wake-lock` + Termux:Boot (F-Droid) are what
keep it alive across reboots.

## Verification (live, 2026-11-13)

The phone install is **VERIFIED LIVE** on a phone — a Debian 12 QEMU VM
in Termux on a moto g power 2025 / S26 (4 vCPU / 4 GB RAM):

- The admin container is running
  `ghcr.io/thefortressentertainment-pixel/project-nomad-arm64:standard`,
  Up and (healthy), and answers HTTP 302 on `:8080` (login redirect,
  normal).
- 6 ZIMs in the Kiwix data dir, including the 3 baked-in editions:
  Wikipedia top mini 2026-06, CDC Travelers' Health 2024-11, and the
  Medical Library 2024-08.

Earlier checks (2026-11-10, in the build VM):

- `bash -n install/install_nomad.sh` — passes.
- Installer fork-rewrite tested: with
  `NOMAD_SOURCE_REPO=thefortressentertainment-pixel/project-nomad`
  the downloaded compose file's three NOMAD images rewrite to
  `ghcr.io/thefortressentertainment-pixel/project-nomad*`, while
  MySQL/Redis/Dozzle etc. are untouched.
- Docker Hub manifest checks (via hub.docker.com API) — arm64 present
  for: `mysql:8.0`, `redis:7-alpine`, `ollama/ollama:0.33.3`,
  `qdrant/qdrant:v1.16`, `learningequality/kolibri:0.19.4`,
  `dullage/flatnotes:v5.5.4`, `filebrowser/filebrowser:v2`,
  `jellyfin/jellyfin:10.11.11`, `vaultwarden/server:1.36.0`,
  `linuxserver/calibre-web:0.6.26-ls386`, `amir20/dozzle:v10.0`.
- GHCR manifest checks — arm64 present for `kiwix/kiwix-serve:3.8.1`,
  `gchq/cyberchef:10.24.0`, `stirling-tools/s-pdf:2.13.1`,
  `corentinth/it-tools:2024.10.22-7ca5933`, `meshtastic/web:2.7.1`,
  `axistem-dev/meshcore-web:v1.45.0`, and `sysadminsmedia/homebox:0.26.2`.
  No GHCR catalog image is left unverified.
- **New blocker found: `excalidraw/excalidraw:sha-4bfc5bb` is amd64-only.**
  Do not install Excalidraw on ARM unless a multi-arch tag is found.

## Compared to the existing community fork

`eglische/project-nomad-rpi` is a Pi 5 fork with an adapted installer.
This branch is a smaller, upstream-tracking alternative: it keeps
the upstream layout, only changes the arch gate, the CI platforms,
and the NVIDIA skip, and documents Translate as the one service to
drop. If the Pi fork already works for you, use it — this branch is
for keeping close to upstream v1.35.1.
