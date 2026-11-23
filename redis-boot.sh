#!/bin/sh
set -eu
: "${REDIS_PASSWORD:?REDIS_PASSWORD is not set}"
# Railway mounts the volume root-owned; chown it, then let the stock entrypoint drop to the redis user.
chown -R redis:redis /data
exec docker-entrypoint.sh redis-server --requirepass "$REDIS_PASSWORD" --appendonly yes --dir /data
