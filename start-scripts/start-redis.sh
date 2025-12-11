#!/bin/sh
set -e

# Export the default variables
set -a
. "${REDIS_CONFIG_DIR}/defaults.env"
set +a

# Substitute variables in the template and save the updated config file
TARGET_CONFIG=${REDIS_CONFIG_FILE:-"/data/redis.conf"}
envsubst < "${REDIS_CONFIG_DIR}/redis.conf" > "$TARGET_CONFIG"

# Remove config lines for empty password
if [ -z "$REDIS_PRIMARY_PASSWORD" ]; then
  sed -i '/^requirepass /d' "$TARGET_CONFIG"
  sed -i '/^masterauth /d' "$TARGET_CONFIG"
  sed -i '/^masteruser /d' "$TARGET_CONFIG"
fi

# Run Redis instance
echo "${TARGET_CONFIG}:" && cat "$TARGET_CONFIG"
exec redis-server "$TARGET_CONFIG" --port "$REDIS_PRIMARY_PORT" "$@"
