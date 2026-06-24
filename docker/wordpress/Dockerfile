# ============================================================================
# WordPress Custom Image - PHP 8.3 FPM Alpine + Redis Extension
# ============================================================================
ARG WORDPRESS_VERSION=6-php8.3-fpm-alpine
FROM wordpress:${WORDPRESS_VERSION}

# ── Install Redis PHP extension and healthcheck tools ───────────────────────
RUN apk add --no-cache \
        fcgi \
    && apk add --no-cache --virtual .build-deps \
        ${PHPIZE_DEPS} \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps \
    && rm -rf /tmp/* /var/cache/apk/*

# ── Copy custom PHP configuration ──────────────────────────────────────────
COPY php-custom.ini /usr/local/etc/php/conf.d/zz-custom.ini
COPY www.conf /usr/local/etc/php-fpm.d/zz-www.conf

# ── Healthcheck via PHP-FPM ping ───────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=30s \
    CMD SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET \
        cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1

EXPOSE 9000
