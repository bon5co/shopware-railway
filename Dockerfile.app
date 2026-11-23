# upstream: shopware/shopware-cli
FROM shopware/shopware-cli:0.20.0-php-8.4@sha256:e0eee4c7f588e3668a748f2ae8c65a4689365646edc521fba959d32b81674cef AS build

# Shopware 6.7.16.1 (newest release at build time), installed the way upstream's own docker recipe builds it: composer project,
# the docker recipe and the deployment helper (the `/setup` script of the base image runs the helper), then `shopware-cli project ci`
# compiles the administration and storefront assets into the image so a deploy never runs composer or npm.
WORKDIR /src
RUN composer create-project shopware/production:6.7.16.1 . --no-interaction --no-scripts \
 && composer require shopware/docker:0.3.0 shopware/deployment-helper:0.1.13 --no-interaction --no-scripts
ENV SHOPWARE_CACHE_ID=docker
RUN /usr/local/bin/entrypoint.sh shopware-cli project ci /src

# upstream: none Shopware's PHP 8.4 + nginx + supervisord base image, not the application
FROM shopware/docker-base:8.4.19-nginx@sha256:94bc3c74588c75586e501fbfc746607d7ed50678c5b4f04a65d6d07a783b9efb

ENV APP_ENV=prod \
    SHOPWARE_DISABLE_UPDATE_CHECK=1 \
    SHOPWARE_HTTP_CACHE_ENABLED=1 \
    INSTALL_ADMIN_USERNAME=admin \
    INSTALL_LOCALE=en-GB \
    INSTALL_CURRENCY=USD \
    TRUSTED_PROXIES=REMOTE_ADDR \
    SYMFONY_TRUSTED_HEADERS=x-forwarded-for,x-forwarded-host,x-forwarded-proto,x-forwarded-port,x-forwarded-prefix \
    MESSENGER_TRANSPORT_DSN=doctrine://default?auto_setup=0 \
    PHP_MEMORY_LIMIT=1024m \
    FPM_PM_MAX_CHILDREN=8 \
    FPM_PM_START_SERVERS=3 \
    FPM_PM_MIN_SPARE_SERVERS=2 \
    FPM_PM_MAX_SPARE_SERVERS=4

COPY --from=build --chown=82:82 /src /var/www/html
COPY --chmod=755 railway-boot.sh /usr/local/bin/railway-boot.sh
COPY supervisord.conf /etc/supervisord.railway.conf
COPY --chmod=644 railway.yaml /var/www/html/config/packages/railway.yaml
COPY --chmod=644 healthz.php /usr/local/share/healthz.php
USER root
ENTRYPOINT ["/bin/sh", "/usr/local/bin/railway-boot.sh"]
