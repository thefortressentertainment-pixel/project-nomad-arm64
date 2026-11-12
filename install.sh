#!/bin/bash
#
# Project NOMAD — ARM64 easy installer (bootstrap)
#
# One command to install Project NOMAD on ARM64 (and x86_64) Debian/Ubuntu:
#
#   curl -fsSL https://raw.githubusercontent.com/thefortressentertainment-pixel/project-nomad-arm64/main/install.sh -o /tmp/nomad-arm-install.sh && bash /tmp/nomad-arm-install.sh
#
# What it does:
#   1. Checks you are on Debian/Ubuntu, on ARM64 or x86_64, with sudo.
#   2. Checks the fork's multi-arch Docker images are published on GHCR
#      (so the install does not fail halfway through downloading).
#   3. Downloads the full installer and runs it. The installer asks two
#      questions (continue? accept the licence?), installs Docker if it is
#      missing, downloads NOMAD, and starts it.
#
# You can point it at a different repo/branch if you know what you are doing:
#   NOMAD_SOURCE_REPO=someone/project-nomad-arm64 NOMAD_SOURCE_BRANCH=main bash install.sh
#
# Plain-language guide: INSTALL-EASY.md. Phone setup: README-ARM.md.

set -u

REPO="${NOMAD_SOURCE_REPO:-thefortressentertainment-pixel/project-nomad-arm64}"
BRANCH="${NOMAD_SOURCE_BRANCH:-main}"
INSTALLER_URL="https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/install/install_nomad.sh"
OWNER="${REPO%%/*}"
OWNER_LOWER="$(echo "$OWNER" | tr '[:upper:]' '[:lower:]')"
# The published image is named after the repo itself (e.g. the fork
# thefortressentertainment-pixel/project-nomad-arm64 publishes
# ghcr.io/thefortressentertainment-pixel/project-nomad-arm64), not
# "project-nomad" — checking the wrong name would wrongly report the
# images as unpublished.
REPO_NAME="${REPO##*/}"
REPO_NAME_LOWER="$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]')"

say()  { echo "==> $*"; }
warn() { echo "!!  $*" >&2; }
die()  { echo "XX  $*" >&2; exit 1; }

# --- Pre-flight checks -------------------------------------------------------

if [[ -z "${BASH_VERSION:-}" ]]; then
  die "This installer needs bash. Please run it with: bash install.sh"
fi

if [[ ! -f /etc/debian_version ]]; then
  die "This installer only works on Debian or Ubuntu. You are not on a Debian-based system."
fi

arch="$(uname -m)"
case "$arch" in
  aarch64|arm64)
    say "ARM64 detected ($arch) — installing the ARM64 port of Project NOMAD."
    say "Note: on ARM the AI runs on the CPU only, and the Translate service is not available."
    ;;
  x86_64|amd64)
    say "x86_64 detected ($arch) — installing Project NOMAD."
    ;;
  *)
    die "Your processor ($arch) is not supported. This installer supports ARM64 and x86_64."
    ;;
esac

if ! sudo -n true 2>/dev/null && ! sudo true 2>/dev/null; then
  die "This installer needs sudo (administrator) access. Please run it from an account that can use sudo."
fi

if ! command -v curl >/dev/null 2>&1; then
  say "curl is missing — installing it..."
  sudo apt-get update && sudo apt-get install -y curl || die "Could not install curl."
fi

# --- Check the Docker images are published ----------------------------------
# The fork's CI builds the NOMAD images for ARM64 and x86_64. If those images
# have not been published yet, the install would fail much later while
# downloading, so check first and say so in plain language.

say "Checking that the Project NOMAD images are ready to download..."
ghcr_ok="unknown"
if token="$(curl -fsSL --max-time 20 "https://ghcr.io/token?scope=repository:${OWNER_LOWER}/${REPO_NAME_LOWER}:pull" 2>/dev/null | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"; then
  if [[ -n "$token" ]]; then
    if tags="$(curl -fsSL --max-time 20 -H "Authorization: Bearer $token" "https://ghcr.io/v2/${OWNER_LOWER}/${REPO_NAME_LOWER}/tags/list" 2>/dev/null)"; then
      if echo "$tags" | grep -q '"latest"'; then
        ghcr_ok="yes"
      else
        ghcr_ok="no"
      fi
    fi
  fi
fi

if [[ "$ghcr_ok" == "no" ]]; then
  warn ""
  warn "The Project NOMAD images have not been published for this fork yet."
  warn "The install would fail when it tries to download them."
  warn "Before installing, run the three build workflows on GitHub"
  warn "(Build Primary Docker Image, Build Sidecar Updater Image, and"
  warn "Build Disk Collector Image) with a version number and 'Also tag"
  warn "this image as :latest?' ticked. See README-ARM.md."
  warn ""
  read -r -p "Continue anyway? (y/N): " choice
  case "$choice" in
    y|Y) say "Continuing anyway, as requested." ;;
    *)   die "Stopped. Publish the images first, then run this installer again." ;;
  esac
elif [[ "$ghcr_ok" == "unknown" ]]; then
  warn "Could not check whether the images are published (no reply from the image registry)."
  warn "Continuing — if the download fails later, that is probably why."
else
  say "Images are published. Good to go."
fi

# --- Download and run the full installer ------------------------------------

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
installer="$tmpdir/install_nomad.sh"

say "Downloading the Project NOMAD installer..."
curl -fsSL --retry 3 "$INSTALLER_URL" -o "$installer" || die "Could not download the installer from $INSTALLER_URL. Check your internet connection and try again."
[[ -s "$installer" ]] || die "The downloaded installer is empty. Please try again."
chmod +x "$installer"

say ""
say "Starting the Project NOMAD installer. It will ask you two questions"
say "(whether to continue, and whether you accept the licence), then it"
say "does the rest. This can take a while on a first install — the"
say "downloads are large, and slower on a phone. Please be patient."
say ""

NOMAD_SOURCE_REPO="$REPO" NOMAD_SOURCE_BRANCH="$BRANCH" sudo -E bash "$installer"

say ""
say "Done. If the installer finished successfully, open Project NOMAD at"
say "http://localhost:8080 (or the address it printed at the end)."
say "Full guide: INSTALL-EASY.md in the same repository."
