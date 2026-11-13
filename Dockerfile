FROM node:22-slim AS base

# Install bash & curl for entrypoint script compatibility, graphicsmagick for pdf2pic, and vips-dev & build-base for sharp 
RUN apt-get update && apt-get install -y \
      bash \
      curl \
      openssl \
      graphicsmagick \
      libvips-dev \
      build-essential \
      pciutils \
      && rm -rf /var/lib/apt/lists/*

# All deps stage
FROM base AS deps
WORKDIR /app
ADD admin/package.json admin/package-lock.json ./
RUN npm ci

# Production only deps stage
FROM base AS production-deps
WORKDIR /app
ADD admin/package.json admin/package-lock.json ./
RUN npm ci --omit=dev

# Build stage
FROM base AS build
WORKDIR /app
COPY --from=deps /app/node_modules /app/node_modules
ADD admin/ ./
# Regenerate the curated drug-reference data modules
# (app/data/{conditions,natural_remedies,home_remedies}.ts) from their single
# source of truth — the repo-root collections/*.json — so the JSON is what gets
# compiled into the image and the committed .ts can never silently drift from it
# in a build. The gen script resolves ../../collections relative to admin/scripts,
# which is /collections once admin/ has been copied to /app.
COPY collections/ /collections/
RUN npm run gen:curated-data
RUN node ace build

# --- Bundled ZIM content (image variants) -----------------------------------
# One stage downloads every ZIM any variant needs, from the same
# download.kiwix.org URLs the Content Manager uses at runtime (see
# collections/wikipedia.json and collections/kiwix-categories.json). Each
# file is SHA256-verified, so a tampered or truncated download fails the
# build instead of shipping a broken library. Variant stages below COPY
# only the ZIMs they need out of this stage, so each image carries just
# its own content set. The 100-mini ZIM is copied from the repo instead
# (install/wikipedia_en_100_mini_2026-01.zim, restored from binary-blocks),
# because it is already in the build context.
# NOTE: downloading all ZIMs in one stage means building any single variant
# fetches the whole set (~740 MB) once; the layer is cached and shared by
# every variant build in the same CI job.
FROM base AS zim-content
ARG ZIM_TOPMINI_SHA256=2bcb45123f661b26ea6f1b1bf9d6b52caef6d2fb777507a0de3072b0c8df30ee
ARG ZIM_CDC_SHA256=45c1c8d79a38a814098be41044a42d4ac7cc3dfa5cdfe398e9974e08d80591dc
ARG ZIM_MEDICINE_SHA256=a86c31b93e9800aae2cd812ef18cbf9c087a7537784c62fbc259db7f9f9d18c0
ARG ZIM_MILITARY_SHA256=9fc5e5d0302504f57a33e0d3aad9c94761cfd6caab22354ed04b9e9bad2ff57f
ARG ZIM_NHS_SHA256=7dfa9bffa286e1ed4442536e746109a58d678bc6681af0b9881e07b7ef3dae28
ARG ZIM_HAM_SHA256=cb8a0cd7ae0078279ace1cd2a05e60505aa2494c29e82dac1942bf4cd54fcf9c
RUN set -eux; \
    mkdir -p /zim; \
    cd /tmp; \
    curl -fsSL --retry 3 -o wikipedia_en_top_mini_2026-06.zim \
      "https://download.kiwix.org/zim/wikipedia/wikipedia_en_top_mini_2026-06.zim"; \
    echo "${ZIM_TOPMINI_SHA256}  wikipedia_en_top_mini_2026-06.zim" | sha256sum -c -; \
    curl -fsSL --retry 3 -o wwwnc.cdc.gov_en_all_2024-11.zim \
      "https://download.kiwix.org/zim/zimit/wwwnc.cdc.gov_en_all_2024-11.zim"; \
    echo "${ZIM_CDC_SHA256}  wwwnc.cdc.gov_en_all_2024-11.zim" | sha256sum -c -; \
    curl -fsSL --retry 3 -o zimgit-medicine_en_2024-08.zim \
      "https://download.kiwix.org/zim/other/zimgit-medicine_en_2024-08.zim"; \
    echo "${ZIM_MEDICINE_SHA256}  zimgit-medicine_en_2024-08.zim" | sha256sum -c -; \
    curl -fsSL --retry 3 -o irp.fas.org_en_military-medicine_2026-10.zim \
      "https://download.kiwix.org/zim/zimit/irp.fas.org_en_military-medicine_2026-10.zim"; \
    echo "${ZIM_MILITARY_SHA256}  irp.fas.org_en_military-medicine_2026-10.zim" | sha256sum -c -; \
    curl -fsSL --retry 3 -o nhs.uk_en_medicines_2025-12.zim \
      "https://download.kiwix.org/zim/zimit/nhs.uk_en_medicines_2025-12.zim"; \
    echo "${ZIM_NHS_SHA256}  nhs.uk_en_medicines_2025-12.zim" | sha256sum -c -; \
    curl -fsSL --retry 3 -o ham.stackexchange.com_en_all_2026-10.zim \
      "https://download.kiwix.org/zim/stack_exchange/ham.stackexchange.com_en_all_2026-10.zim"; \
    echo "${ZIM_HAM_SHA256}  ham.stackexchange.com_en_all_2026-10.zim" | sha256sum -c -; \
    mv wikipedia_en_top_mini_2026-06.zim wwwnc.cdc.gov_en_all_2024-11.zim zimgit-medicine_en_2024-08.zim irp.fas.org_en_military-medicine_2026-10.zim nhs.uk_en_medicines_2025-12.zim ham.stackexchange.com_en_all_2026-10.zim /zim/
# 100-mini comes from the repo (already in the build context, hash-verified).
COPY install/wikipedia_en_100_mini_2026-01.zim /zim/wikipedia_en_100_mini_2026-01.zim
RUN echo "2811724b72fd34a0728c28b7456d3d6866579019fbbe7ffe28528f3450c252db  /zim/wikipedia_en_100_mini_2026-01.zim" | sha256sum -c -

# Production stage
FROM base
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF
ARG TARGETARCH

# go-pmtiles (regional map extracts). Pinned so the CLI's stdout format stays
# in sync with parseDryRunOutput().
ARG PMTILES_VERSION=1.30.2
# Upstream releases don't ship a checksums file, so pin per-arch SHA256 here.
# When bumping PMTILES_VERSION, regenerate these with:
#   curl -fsSL <release-url> | sha256sum
ARG PMTILES_SHA256_AMD64=2cd3aa18868297fc88425038f794efdc0995e0275f4ca16fa496dd79e245a40c
ARG PMTILES_SHA256_ARM64=804cdf071834e1156af554c1a26cc42b56b9cde5a2db9c6e3653d16fb846d5fa
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) PMTILES_ARCH=x86_64; PMTILES_SHA256="${PMTILES_SHA256_AMD64}" ;; \
      arm64) PMTILES_ARCH=arm64;  PMTILES_SHA256="${PMTILES_SHA256_ARM64}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    TARBALL="go-pmtiles_${PMTILES_VERSION}_Linux_${PMTILES_ARCH}.tar.gz"; \
    cd /tmp; \
    curl -fsSL -o "$TARBALL" \
      "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/${TARBALL}"; \
    echo "${PMTILES_SHA256}  ${TARBALL}" | sha256sum -c -; \
    tar -xzf "$TARBALL" -C /usr/local/bin pmtiles; \
    rm -f "$TARBALL"; \
    chmod +x /usr/local/bin/pmtiles; \
    /usr/local/bin/pmtiles version

# Labels
LABEL org.opencontainers.image.title="Project NOMAD" \
      org.opencontainers.image.description="The Project NOMAD Official Docker image" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.vendor="Crosstalk Solutions, LLC" \
      org.opencontainers.image.documentation="https://github.com/CrosstalkSolutions/project-nomad/blob/main/README.md" \
      org.opencontainers.image.source="https://github.com/CrosstalkSolutions/project-nomad" \
      org.opencontainers.image.licenses="Apache-2.0"

ENV NODE_ENV=production

# Creator Packs entitlement key, injected into OFFICIAL release builds at build
# time (--build-arg CREATOR_PACKS_APP_KEY=... from the CREATOR_PACKS_APP_KEY CI
# secret; see build-primary-image.yml). Baked as an ENV so admin/start/env.ts
# reads it at runtime. Empty by default, so builds from source (and any build
# without the secret) ship UNCONFIGURED and hide the Creator Packs UI. The key
# lands in this public image layer (extractable — the accepted ceiling); rotate
# via `wrangler secret put APP_KEY` + a new image if it leaks.
ARG CREATOR_PACKS_APP_KEY=""
ENV CREATOR_PACKS_APP_KEY=$CREATOR_PACKS_APP_KEY

WORKDIR /app
COPY --from=production-deps /app/node_modules /app/node_modules
COPY --from=build /app/build /app
# Copy static public files (favicons, docs images, banners, creator packs)
# that the AdonisJS build does not reliably include in the build output, so
# the docs images and favicons actually serve. This merges with the built
# /app/public: admin/public/assets is empty in source, so the built frontend
# assets are preserved.
COPY admin/public /app/public
# Fail the build loudly if the static files did not land. Run #7 shipped an
# image whose /app/public held only assets/ + 2 SVGs, so /docs/dashboard.webp
# 500'd and every favicon 404'd, and nothing in the build log said so. If
# this COPY ever silently misses again, the build stops here instead of
# publishing a broken image.
RUN test -f /app/public/docs/dashboard.webp && test -f /app/public/favicon-32x32.png && test -f /app/public/favicon-16x16.png && test -f /app/public/favicon-192x192.png && ls /app/public/docs | head -20
# Generate version.json from the VERSION build-arg so the image tag is the
# single source of truth (previously copied root package.json, which drifted
# from the tag when semantic-release did not commit the bump back).
RUN echo "{\"version\":\"${VERSION}\"}" > /app/version.json

# Copy docs and README for access within the container
COPY admin/docs /app/docs
COPY README.md /app/README.md

# Empty Calibre library, seeded into storage/books on Calibre-Web install
# (see DockerService._runPreinstallActions__CalibreWeb).
# NOTE (arm64-port): the .db is stored in git only as a base64 chunk
# (binary-blocks/020-...), because the push route used for this fork accepts
# text only — it is NOT a tracked file on main, so the workflow restores it
# before building. Run #4 proved the restored file is in the workspace yet
# the arm64 builder still cannot see it at this COPY, so decode the tracked
# chunk inside the image instead: the chunk IS in git, so it is definitely
# in the build context, and the build no longer depends on the restore step
# for the one file that can fail it. Hash-verified against the manifest.
COPY binary-blocks/020-install__calibre-empty-library__metadata.db.b64 /tmp/metadata.db.b64
RUN mkdir -p /app/assets/calibre && base64 -d /tmp/metadata.db.b64 > /app/assets/calibre/metadata.db && echo "ad8a3bc3612725ef761a089ccc820a91d6b228117403514837356a0b366b6af3  /app/assets/calibre/metadata.db" | sha256sum -c - && rm /tmp/metadata.db.b64

# Copy entrypoint script and ensure it's executable
COPY install/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# --- Image variants (content editions) ---------------------------------------
# Each variant is the production image plus a baked-in ZIM set in
# /app/bundled-zim. The entrypoint copies bundled ZIMs into /app/storage/zim
# on first boot (never overwriting), so a fresh install has offline content
# with no separate download. /app/storage is a bind mount at runtime, so
# ZIMs must live in /app/bundled-zim in the image — anything baked into
# /app/storage would be shadowed by the mount.
#   lite     — Wikipedia 100-mini only (~4 MB). Smallest pull, low-storage phones.
#   standard — Wikipedia top-mini + CDC + Medicine (~580 MB). General offline library.
#   comms    — Wikipedia 100-mini + Ham Radio Q&A (~80 MB). Mesh radio users;
#              the installer also pre-pulls the Meshtastic/MeshCore images.
#   full     — Every ZIM above (~740 MB). The complete kit.
# Build with: docker build --target variant-<name> .
# The plain :latest image is unchanged (no bundled ZIMs); variants are
# additive tags (:lite, :standard, :comms, :full).

FROM production AS variant-lite
ENV NOMAD_VARIANT=lite
LABEL org.opencontainers.image.variant="lite"
COPY --from=zim-content /zim/wikipedia_en_100_mini_2026-01.zim /app/bundled-zim/

FROM production AS variant-standard
ENV NOMAD_VARIANT=standard
LABEL org.opencontainers.image.variant="standard"
COPY --from=zim-content /zim/wikipedia_en_top_mini_2026-06.zim /app/bundled-zim/
COPY --from=zim-content /zim/wwwnc.cdc.gov_en_all_2024-11.zim /app/bundled-zim/
COPY --from=zim-content /zim/zimgit-medicine_en_2024-08.zim /app/bundled-zim/

FROM production AS variant-comms
ENV NOMAD_VARIANT=comms
LABEL org.opencontainers.image.variant="comms"
COPY --from=zim-content /zim/wikipedia_en_100_mini_2026-01.zim /app/bundled-zim/
COPY --from=zim-content /zim/ham.stackexchange.com_en_all_2026-10.zim /app/bundled-zim/

FROM production AS variant-full
ENV NOMAD_VARIANT=full
LABEL org.opencontainers.image.variant="full"
COPY --from=zim-content /zim/wikipedia_en_top_mini_2026-06.zim /app/bundled-zim/
COPY --from=zim-content /zim/wwwnc.cdc.gov_en_all_2024-11.zim /app/bundled-zim/
COPY --from=zim-content /zim/zimgit-medicine_en_2024-08.zim /app/bundled-zim/
COPY --from=zim-content /zim/irp.fas.org_en_military-medicine_2026-10.zim /app/bundled-zim/
COPY --from=zim-content /zim/nhs.uk_en_medicines_2025-12.zim /app/bundled-zim/
COPY --from=zim-content /zim/wikipedia_en_100_mini_2026-01.zim /app/bundled-zim/
COPY --from=zim-content /zim/ham.stackexchange.com_en_all_2026-10.zim /app/bundled-zim/

# Default target: the plain production image, exactly as before (no bundled
# ZIMs). This stage exists so a bare `docker build` (no --target) still
# produces the same image :latest has always been, and the variant stages
# above it are only built when explicitly targeted. Variants are additive.
FROM production AS release