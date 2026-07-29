#!/usr/bin/env bash
set -e

# Configuration
export MIX_ENV=prod
export PORT=${PORT:-4000}

# Replace this with your actual generated secret:
export SECRET_KEY_BASE="PASTE_YOUR_GENERATED_SECRET_KEY_HERE"

# Explicitly point to local PostgreSQL (adjust username/password/dbname if needed)
export DATABASE_URL="ecto://postgres:postgres@localhost:5432/tcc_depeering_elixir"

APP_NAME="tcc_depeering_elixir"
RELEASE_BIN="_build/prod/rel/${APP_NAME}/bin/${APP_NAME}"

echo "=========================================="
echo " Preparing Environment & Starting Release"
echo "=========================================="

# Stop any lingering background nodes
$RELEASE_BIN stop 2>/dev/null || true
pkill -9 -f beam.smp || true

echo "--> Restarting PostgreSQL service..."
sudo -u postgres /usr/local/pgsql/bin/pg_ctl stop -D /usr/local/pgsql/data -m fast || true
sudo -u postgres /usr/local/pgsql/bin/pg_ctl start -D /usr/local/pgsql/data -l /usr/local/pgsql/data/server.log

echo "--> Ensuring database exists..."
sudo -u postgres /usr/local/pgsql/bin/createdb tcc_depeering_elixir 2>/dev/null || true

echo "--> Clearing port ${PORT}..."
fuser -k ${PORT}/tcp || true

echo "--> Starting ${APP_NAME} server on port ${PORT}..."
$RELEASE_BIN start