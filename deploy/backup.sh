#!/bin/sh
# Ночная резервная копия базы и файлов меню. Сервер не останавливается.
# Запускается cron'ом сервера (см. deploy/README.md):
#   0 3 * * * /srv/menu/deploy/backup.sh >> /srv/menu/deploy/backups/backup.log 2>&1
set -eu
cd "$(dirname "$0")"
echo "=== $(date '+%Y-%m-%d %H:%M:%S')"
docker compose exec -T menu /app/server/bin/server backup /backups --keep=14
