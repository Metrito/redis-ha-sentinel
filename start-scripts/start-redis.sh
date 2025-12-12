#!/bin/sh
set -e

# Export the default variables
set -a
. "${REDIS_CONFIG_DIR}/defaults.env"
set +a

# Export the address variables (internal or external)
if [ -z "$REDIS_FLAG_EXT_ADDR" ]; then
  export REDIS_ANNOUNCE_IP='""'
  export REDIS_ANNOUNCE_PORT=0
else
  export REDIS_ANNOUNCE_IP="${REDIS_ANNOUNCE_IP:-host.docker.internal}"
  export REDIS_ANNOUNCE_PORT="${REDIS_ANNOUNCE_PORT:-6379}"
fi

# Substitute variables in the template and save the updated config file
TARGET_CONFIG=${REDIS_CONFIG_FILE:-"/data/redis.conf"}
envsubst < "${REDIS_CONFIG_DIR}/primary.conf" > "$TARGET_CONFIG"

# Remove config lines for empty password
if [ -z "$REDIS_AUTH_PASSWORD" ]; then
  sed -i '/^requirepass /d' "$TARGET_CONFIG"
  sed -i '/^masterauth /d' "$TARGET_CONFIG"
  sed -i '/^masteruser /d' "$TARGET_CONFIG"
fi

# Run Redis instance
echo "${TARGET_CONFIG}:" && cat "$TARGET_CONFIG"
exec redis-server "$TARGET_CONFIG" "$@"
