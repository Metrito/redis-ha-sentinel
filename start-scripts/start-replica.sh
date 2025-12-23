#!/bin/sh
set -e

# Build the ACL password rule
if [ -z "$REDIS_AUTH_PASSWORD" ]; then
  export REDIS_ACL_RULE_PASSWORD="nopass"
else
  export REDIS_ACL_RULE_PASSWORD=">${REDIS_AUTH_PASSWORD}"
fi

# Export the address variables (internal or external)
if [ -z "$REDIS_FLAG_EXT_ADDR" ]; then
  export REDIS_ANNOUNCE_IP='""'
  export REDIS_ANNOUNCE_PORT=0
else
  export REDIS_ANNOUNCE_IP="${REDIS_ANNOUNCE_IP:-host.docker.internal}"
  export REDIS_ANNOUNCE_PORT="${REDIS_ANNOUNCE_PORT:-6379}"
  export REDIS_REPLICA_PRIMARY_HOST="${REDIS_EXT_PRIMARY_HOST:-$REDIS_ANNOUNCE_IP}"
  export REDIS_REPLICA_PRIMARY_PORT="${REDIS_EXT_PRIMARY_PORT:-6379}"
fi

# Export the other default variables
set -a
. "${REDIS_TEMPLATE_CONFIG_DIR}/defaults.env"
set +a

# Prepare the Redis working directory
if [ -n "$COMPOSE_SERVICE_NAME" ]; then
  PTR=$(nslookup $(hostname -i) | grep 'in-addr.arpa')
  INDEX=$(echo $PTR | sed -n "s/.*${COMPOSE_SERVICE_NAME}-\([0-9]*\)\..*/\1/p")
  if [ -n "$INDEX" ]; then
    # Compose service instances must work in a subfolder
    REDIS_REPLICA_DIR="${REDIS_REPLICA_DIR}${COMPOSE_SERVICE_NAME}__${INDEX}/"
  fi
fi
mkdir -p "$REDIS_REPLICA_DIR"
cd "$REDIS_REPLICA_DIR"

# Substitute variables in the template and save the updated config file
CONFIG_DIR="/usr/local/etc/redis"
CONFIG_FILE="${CONFIG_DIR}/redis.conf"
mkdir -p "$CONFIG_DIR"
envsubst < "${REDIS_TEMPLATE_CONFIG_DIR}/replica.conf" > "$CONFIG_FILE"

# Make sure the config folder is owned and writable by redis
ERR=$(chown -R redis "$CONFIG_DIR" 2>&1) || echo "ERROR on chown: $ERR"
ERR=$(chmod -R u+rwX,g+X,o+X "$CONFIG_DIR" 2>&1) || echo "ERROR on chmod: $ERR"

# Run the default entrypoint and start Redis instance
echo "PWD: $PWD CONF: $CONFIG_FILE CAT:" $(cat "$CONFIG_FILE" | tr '\n' ' ')
exec docker-entrypoint.sh redis-server "$CONFIG_FILE" "$@"
