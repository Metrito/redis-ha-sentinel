#!/bin/bash

HOST=${1:-"host.docker.internal"}
ENV_FILE=${2:-".env"}
SERVICES=${3:-"redis-primary redis-replica redis-sentinel"}
if [ -z "$HOST" ] || [ ! -f "$ENV_FILE" ]; then
  echo ">>> Must provide HOST and ENV_FILE"
  exit 1
fi

source "$ENV_FILE"

for SERVICE in $SERVICES; do
  echo ">>> Configuring service $SERVICE"
  for CONTAINER in $(docker compose ps -q $SERVICE 2>/dev/null); do
    for PORT in $(docker port $CONTAINER | sed -e 's/.*://'); do
      echo ">>> Announce host $HOST and port $PORT on container $CONTAINER"
      case $SERVICE in
        "redis-primary" | "redis-replica")
          REDIS_INTERNAL_PORT=${REDIS_PRIMARY_PORT:-6379}
          PASS=${REDIS_AUTH_PASSWORD:+"-a $REDIS_AUTH_PASSWORD"}
          docker exec $CONTAINER redis-cli -p $REDIS_INTERNAL_PORT $PASS \
            CONFIG SET replica-announce-ip "$HOST" replica-announce-port "$PORT"
          ;;
        "redis-sentinel")
          REDIS_INTERNAL_PORT=${REDIS_SENTINEL_PORT:-26379}
          PASS=${REDIS_AUTH_SENTINEL_PASSWORD:+"-a $REDIS_AUTH_SENTINEL_PASSWORD"}
          docker exec $CONTAINER redis-cli -p $REDIS_INTERNAL_PORT $PASS \
            SENTINEL CONFIG SET announce-ip "$HOST" announce-port "$PORT"
          ;;
        *)
          echo ">>> Unexpected service $SERVICE"
          continue
          ;;
      esac
      echo ">>> Docker exec result: $?"
    done
  done
done
