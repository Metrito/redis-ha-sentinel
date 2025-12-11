#!/bin/sh
set -e

# Export the default variables
set -a
. "${REDIS_CONFIG_DIR}/defaults.env"
set +a

# Run Redis instance as a replica
exec start-redis.sh --port "${REDIS_REPLICA_PORT:-6379}" \
  --replicaof "$REDIS_PRIMARY_HOST" "$REDIS_PRIMARY_PORT" "$@"
