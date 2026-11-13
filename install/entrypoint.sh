#!/bin/sh

set -e

echo "Starting entrypoint script..."

# Ensure required storage directories exist (volume may be freshly mounted)
mkdir -p /app/storage/logs /app/storage/kb_uploads

# Seed bundled ZIM content (image variants): variant images bake ZIM files
# into /app/bundled-zim at build time. On first boot, copy any that are not
# already in the storage volume so a fresh install has offline content with
# no separate download. Never overwrites files already in storage (a user
# may have a newer version there). The admin rebuilds the Kiwix library XML
# from the ZIMs on disk at boot if it is missing, so seeded files are picked
# up automatically. No-op for the plain :latest image (no bundled ZIMs).
if [ -d /app/bundled-zim ]; then
  mkdir -p /app/storage/zim
  for zim in /app/bundled-zim/*.zim; do
    [ -e "$zim" ] || continue
    name="$(basename "$zim")"
    if [ -e "/app/storage/zim/$name" ]; then
      echo "Bundled ZIM already in storage, skipping: $name"
    else
      echo "Seeding bundled ZIM into storage: $name"
      # Non-fatal: a failed copy (e.g. disk full) must not stop NOMAD from
      # starting — the content can still be downloaded later from the UI.
      cp "$zim" "/app/storage/zim/$name" || echo "Warning: could not seed $name (disk full?). It can be downloaded later from the Content Manager." >&2
    fi
  done
fi

# Wait for Redis to be reachable before booting anything that opens a BullMQ
# connection. `depends_on: condition: service_healthy` only gates a clean
# `up --recreate`; it is NOT re-checked on `docker compose restart` or a
# `restart: unless-stopped` bounce, so without this the app can race Docker's
# DNS (EAI_AGAIN) or dial a restarted Redis container's stale IP (ECONNREFUSED).
# This isn't load-bearing since legacy installs used a mounted entrypoint script
# that may override this script, but it's a cost-nothing check for newer installs.
# The real check is done by the application itself, but this provides a safety net.
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
echo "Waiting for Redis at ${REDIS_HOST}:${REDIS_PORT}..."
for i in $(seq 1 60); do
  if node -e "const net=require('net');const s=net.connect(Number(process.env.REDIS_PORT||6379),process.env.REDIS_HOST||'redis');let done=false;const finish=(code)=>{if(done)return;done=true;s.destroy();process.exit(code)};s.setTimeout(1000,()=>finish(1));s.on('connect',()=>finish(0));s.on('error',()=>finish(1));" 2>/dev/null; then
    echo "Redis is up and running!"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "Timed out waiting for Redis at ${REDIS_HOST}:${REDIS_PORT}" >&2
    exit 1
  fi
  sleep 1
done

# Run AdonisJS migrations
echo "Running AdonisJS migrations..."
node ace migration:run --force

# Seed the database if needed
echo "Seeding the database..."
node ace db:seed

# Start background workers for all queues
echo "Starting background workers for all queues..."
node ace queue:work --all &

# Start the AdonisJS application
echo "Starting AdonisJS application..."
exec node bin/server.js
