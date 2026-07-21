

#!/usr/bin/env bash
set -e

# Configuration
export MIX_ENV=prod

echo "=========================================="
echo " Starting Elixir / Phoenix Production Build"
echo "=========================================="

echo "--> Fetching production dependencies..."
mix deps.get --only prod

echo "--> Compiling dependencies..."
mix deps.compile

# If your Phoenix app serves static assets (HTML/LiveView), uncomment the line below:
# echo "--> Building static assets..."
# mix assets.deploy

echo "--> Compiling application code..."
mix compile

echo "--> Generating OTP Release..."
mix release --overwrite

echo "=========================================="
echo " Build Completed Successfully!"
echo " Release location: _build/prod/rel/"
echo "=========================================="