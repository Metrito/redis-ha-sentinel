ARG DOCKER_BUILD_REDIS_IMAGE_TAG_ALPINE=alpine

FROM redis:${DOCKER_BUILD_REDIS_IMAGE_TAG_ALPINE}

RUN set -eux; apk add --no-cache gettext-envsubst tini tzdata;

ENV REDIS_TEMPLATE_CONFIG_DIR="/usr/local/etc/redis-config-templates"
COPY redis-conf $REDIS_TEMPLATE_CONFIG_DIR

COPY start-scripts/* /usr/local/bin/
RUN chmod +x /usr/local/bin/start-*.sh

ENTRYPOINT ["/sbin/tini", "-g", "--", "docker-entrypoint.sh"]

CMD ["start-redis.sh"]
