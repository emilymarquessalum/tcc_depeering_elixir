#!/bin/sh
set -e

# Run migrations
/app/bin/tcc_depeering_elixir eval "TccDepeeringElixir.Release.migrate"

# Start application
exec "$@"