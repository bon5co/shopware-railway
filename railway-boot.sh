#!/bin/sh
# Shopware boot script for Railway: one container runs nginx, php-fpm, the install/migrate step, the message worker and the scheduler.
#
# What Railway forces, against upstream's compose stack (Dokploy's Shopware blueprint, shopware/docker recipe):
#   - one volume per service, so the five upstream volumes (files, theme, media, thumbnail, sitemap) become sub-folders of /data
#     and are symlinked into the code tree; worker and scheduler live in this container because they must share media with the web process;
#   - the volume is mounted root-owned, so it is chowned to www-data (82) before the stack drops to that user;
#   - Railway injects PORT and the healthcheck dials it, so nginx listens on $PORT instead of upstream's 8000;
#   - the database is another service: wait for it before the installer starts;
#   - API tokens are signed with APP_SECRET (Shopware 6.7), a generated template secret, so no key pair is needed.
set -eu
log() { echo "[shopware-boot] $*"; }

: "${MYSQL_PASSWORD:?MYSQL_PASSWORD is not set}"
: "${REDIS_PASSWORD:?REDIS_PASSWORD is not set}"
: "${APP_SECRET:?APP_SECRET is not set}"
: "${INSTANCE_ID:?INSTANCE_ID is not set}"
: "${INSTALL_ADMIN_PASSWORD:?INSTALL_ADMIN_PASSWORD is not set}"

DB_HOST="${DB_HOST:-database.railway.internal}"
REDIS_HOST="${REDIS_HOST:-redis.railway.internal}"
APP=/var/www/html
DATA=/data

export DATABASE_URL="mysql://shopware:${MYSQL_PASSWORD}@${DB_HOST}:3306/shopware?charset=utf8mb4"
export LOCK_DSN="redis://:${REDIS_PASSWORD}@${REDIS_HOST}:6379/1"
export PHP_SESSION_HANDLER=redis
export PHP_SESSION_SAVE_PATH="tcp://${REDIS_HOST}:6379?auth=${REDIS_PASSWORD}"

# APP_URL becomes the storefront's sales-channel domain at first install and never changes after, so it must be right the first time.
# The generate project creates the public domain after the service, so the first deployment can see an empty host: fail fast, the next one has it.
APP_URL="${APP_URL:-}"
case "$APP_URL" in
  https://|http://|"") if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then APP_URL="https://$RAILWAY_PUBLIC_DOMAIN"; else log "APP_URL has no host yet, exiting so Railway retries with the domain"; exit 1; fi ;;
esac
export APP_URL

# --- persistent state on the one volume ---------------------------------------------------------------------------------------
mkdir -p "$DATA/files" "$DATA/public"
for d in media thumbnail theme sitemap; do
  mkdir -p "$DATA/public/$d"
  # a mount hides what the image build wrote, so seed the volume once from the image's copy
  if [ -d "$APP/public/$d" ] && [ ! -L "$APP/public/$d" ] && [ -z "$(ls -A "$DATA/public/$d")" ]; then
    cp -a "$APP/public/$d/." "$DATA/public/$d/" 2>/dev/null || true
  fi
  rm -rf "$APP/public/$d"
  ln -s "$DATA/public/$d" "$APP/public/$d"
done
# private files: config/packages/railway.yaml points the private filesystem root at $DATA/files (a symlink makes flysystem fail with "mkdir(): File exists")
[ -n "$(ls -A "$DATA/files")" ] || cp -a "$APP/files/." "$DATA/files/" 2>/dev/null || true

chown -R 82:82 "$DATA"

# --- nginx: listen on the injected PORT (the healthcheck dials it), both address families -------------------------------------
PORT="${PORT:-8080}"
sed -i "s/listen 8000;/listen ${PORT}; listen [::]:${PORT};/" /etc/nginx/nginx.conf
mkdir -p /etc/nginx/conf.d /tmp/log
# php-fpm and nginx run as www-data and cannot reopen root's stdio pipes (/dev/fd/2), so they log to files that a root `tail` forwards to the container log
sed -i 's#^error_log stderr warn;#error_log /tmp/log/nginx-error.log warn;#; s#error_log /dev/fd/2 warn;#error_log /tmp/log/nginx-error.log warn;#; s#access_log /dev/fd/1 json_combined;#access_log /tmp/log/nginx-access.log json_combined;#' /etc/nginx/nginx.conf
sed -i 's#^error_log = /proc/self/fd/2#error_log = /tmp/log/php-fpm.log#' /usr/local/etc/php-fpm.d/docker.conf
touch /tmp/log/nginx-error.log /tmp/log/nginx-access.log /tmp/log/php-fpm.log
chown -R 82:82 /tmp/log
cat > /etc/nginx/conf.d/healthz.inc <<NGINX
location = /healthz {
    access_log off;
    include fastcgi.conf;
    fastcgi_param SCRIPT_FILENAME /usr/local/share/healthz.php;
    fastcgi_pass unix:/tmp/php-fpm.sock;
}
NGINX

# --- wait for MySQL, then hand over to supervisord (each program drops to www-data itself) ----------------------------------------------------------------
until nc -z -w 3 "$DB_HOST" 3306 >/dev/null 2>&1; do log "waiting for $DB_HOST:3306"; sleep 3; done
until nc -z -w 3 "$REDIS_HOST" 6379 >/dev/null 2>&1; do log "waiting for $REDIS_HOST:6379"; sleep 3; done
log "database and redis reachable, starting"
exec /usr/bin/supervisord -c /etc/supervisord.railway.conf
