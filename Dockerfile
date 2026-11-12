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