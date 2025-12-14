#!/bin/sh
set -e

# Export the default variables
set -a
. "${REDIS_TEMPLATE_CONFIG_DIR}/defaults.env"
set +a

# Export the address variables (internal or external)
if [ -z "$REDIS_FLAG_EXT_ADDR" ]; then
  export REDIS_ANNOUNCE_IP='""'
  export REDIS_ANNOUNCE_PORT=0
else
  export REDIS_ANNOUNCE_IP="${REDIS_ANNOUNCE_IP:-host.docker.internal}"
  export REDIS_ANNOUNCE_PORT="${REDIS_ANNOUNCE_PORT:-26379}"
  export REDIS_SENTINEL_PRIMARY_HOST="${REDIS_EXT_PRIMARY_HOST:-$REDIS_ANNOUNCE_IP}"
  export REDIS_SENTINEL_PRIMARY_PORT="${REDIS_EXT_PRIMARY_PORT:-6379}"
fi

# Prepare the Redis working directory
if [ -n "$COMPOSE_SERVICE_NAME" ]; then
  PTR=$(nslookup $(hostname -i) | grep 'in-addr.arpa')
  INDEX=$(echo $PTR | sed -n "s/.*${COMPOSE_SERVICE_NAME}-\([0-9]*\)\..*/\1/p")
  if [ -n "$INDEX" ]; then
    # Compose service instances must work in a subfolder
    REDIS_SENTINEL_DIR="${REDIS_SENTINEL_DIR}${COMPOSE_SERVICE_NAME}__${INDEX}/"
  fi
fi
mkdir -p "$REDIS_SENTINEL_DIR"
cd "$REDIS_SENTINEL_DIR"

# Substitute variables in the template and save the updated config file
CONFIG_FILE="sentinel.conf"
envsubst < "${REDIS_TEMPLATE_CONFIG_DIR}/sentinel.conf" > "$CONFIG_FILE"

# Remove config lines for empty password
if [ -z "$REDIS_AUTH_SENTINEL" ]; then
  sed -i '/^requirepass /d' "$CONFIG_FILE"
fi

# Remove config lines for empty primary password
if [ -z "$REDIS_AUTH_PASSWORD" ]; then
  sed -i '/^sentinel auth-pass /d' "$CONFIG_FILE"
  sed -i '/^sentinel auth-user /d' "$CONFIG_FILE"
fi

# Run the default entrypoint and start Redis instance
echo "PWD: $PWD CONF: $CONFIG_FILE CAT:" $(cat "$CONFIG_FILE" | tr '\n' ' ')
exec docker-entrypoint.sh redis-server "$CONFIG_FILE" --sentinel "$@"
