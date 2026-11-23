#!/bin/sh
# MySQL boot script for Railway. Settings are the ones Shopware's own compose file passes to its database, minus binary logging
# (no replication here, and the log would fill the volume).
set -eu
: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is not set}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD is not set}"
mkdir -p /var/lib/mysql/data
exec docker-entrypoint.sh mysqld \
  --datadir=/var/lib/mysql/data \
  --bind-address='*' \
  --skip-log-bin \
  --sql-mode=STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION \
  --group_concat_max_len=320000 \
  --default-time-zone=+00:00 \
  --innodb-buffer-pool-size=512M \
  --innodb-log-file-size=128M \
  --character-set-server=utf8mb4
