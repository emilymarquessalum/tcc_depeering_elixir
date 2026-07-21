

#!/usr/bin/env bash
set -e

# Configuration
export MIX_ENV=prod
export PORT=${PORT:-4000}

# Replace 'my_app' with your actual Phoenix application name
APP_NAME="my_app"
RELEASE_BIN="_build/prod/rel/${APP_NAME}/bin/${APP_NAME}"

echo "=========================================="
echo " Preparing Environment & Starting Release"
echo "=========================================="

# Check if release binary exists
if [ ! -f "$RELEASE_BIN" ]; then
    echo "Error: Release binary not found at $RELEASE_BIN"
    echo "Please run build.sh first!"
    exit 1
fi

echo "--> Restarting PostgreSQL service..."
sudo -u postgres /usr/local/pgsql/bin/pg_ctl stop -D /usr/local/pgsql/data -m fast || true
sudo -u postgres /usr/local/pgsql/bin/pg_ctl start -D /usr/local/pgsql/data -l /usr/local/pgsql/data/server.log

echo "--> Clearing port ${PORT}..."
fuser -k ${PORT}/tcp || true

echo "--> Starting ${APP_NAME} server on port ${PORT}..."
$RELEASE_BIN start