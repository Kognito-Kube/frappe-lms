#!/bin/bash
set -e

umask 0002

cd /home/frappe/frappe-bench

# 1. Link baked assets from image layer into the persistent sites volume
ASSETS_PATH="/home/frappe/frappe-bench/sites/assets"
BAKED_PATH="/home/frappe/frappe-bench/assets"

echo "Linking fresh assets to persistent sites volume..."
rm -rf "$ASSETS_PATH"
mkdir -p "/home/frappe/frappe-bench/sites"
ln -s "$BAKED_PATH" "$ASSETS_PATH"

# Clean up ext4 lost+found if present on persistent disk mount
rm -rf /home/frappe/frappe-bench/sites/lost+found 2>/dev/null || true

# 2. Ensure apps.txt and common_site_config.json exist
ls -1 /home/frappe/frappe-bench/apps > /home/frappe/frappe-bench/sites/apps.txt
if [ ! -f /home/frappe/frappe-bench/sites/common_site_config.json ]; then
  echo "{}" > /home/frappe/frappe-bench/sites/common_site_config.json
fi

# 3. Resolve environment defaults
export DB_HOST="${DB_HOST:-mariadb}"
export DB_PORT="${DB_PORT:-3306}"
export REDIS_HOST="${REDIS_HOST:-redis}"
export REDIS_PORT="${REDIS_PORT:-6379}"
export REDIS_URL="${REDIS_URL:-redis://${REDIS_HOST}:${REDIS_PORT}}"
export FRAPPE_SITE_NAME="${FRAPPE_SITE_NAME:-lms.localhost}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-123}"

# 4. Configure common_site_config.json
echo "Configuring common_site_config.json..."
bench set-config -g db_host "$DB_HOST"
bench set-config -gp db_port "$DB_PORT"
bench set-config -g redis_cache "$REDIS_URL"
bench set-config -g redis_queue "$REDIS_URL"
bench set-config -g redis_socketio "$REDIS_URL"
bench set-config -gp socketio_port 9000
bench set-config -g default_site "$FRAPPE_SITE_NAME"
bench set-config -gp serve_default_site true

# 5. Wait for MariaDB and Redis
echo "Waiting for MariaDB at ${DB_HOST}:${DB_PORT}..."
wait-for-it -t 180 "${DB_HOST}:${DB_PORT}"

until mariadb-admin ping -h "$DB_HOST" -P "$DB_PORT" -u root -p"$MYSQL_ROOT_PASSWORD" --silent 2>/dev/null; do
  echo "Waiting for MariaDB to accept root connections..."
  sleep 3
done

if [ -n "$REDIS_HOST" ] && [ -n "$REDIS_PORT" ]; then
  echo "Waiting for Redis at ${REDIS_HOST}:${REDIS_PORT}..."
  wait-for-it -t 120 "${REDIS_HOST}:${REDIS_PORT}"
fi

# 6. Create or migrate the Frappe LMS site
if [ ! -f "/home/frappe/frappe-bench/sites/${FRAPPE_SITE_NAME}/site_config.json" ]; then
  echo "Initializing new Frappe LMS site: ${FRAPPE_SITE_NAME}..."
  bench new-site "${FRAPPE_SITE_NAME}" \
    --force \
    --mariadb-user-host-login-scope='%' \
    --db-root-username=root \
    --db-root-password="${MYSQL_ROOT_PASSWORD}" \
    --admin-password="${ADMIN_PASSWORD}" \
    --no-mariadb-socket \
    --install-app payments \
    --install-app lms \
    --set-default
else
  echo "Site ${FRAPPE_SITE_NAME} already exists. Running database migrations and cache clear..."
  bench --site "${FRAPPE_SITE_NAME}" migrate
  bench --site "${FRAPPE_SITE_NAME}" clear-cache
fi

bench use "${FRAPPE_SITE_NAME}"

# 7. Launch Frappe background services, Socket.IO, Gunicorn, and Nginx
export FRAPPE_REDIS_CACHE="$REDIS_URL"
export FRAPPE_REDIS_QUEUE="$REDIS_URL"

echo "Starting Frappe Socket.IO server on port 9000..."
node /home/frappe/frappe-bench/apps/frappe/socketio.js &

echo "Starting Frappe background workers and scheduler..."
bench worker --queue short,default &
bench worker --queue long,default,short &
bench schedule &

echo "Starting Gunicorn backend on port 8000..."
/usr/local/bin/start.sh &

wait-for-it -t 60 127.0.0.1:8000

export BACKEND="127.0.0.1:8000"
export SOCKETIO="127.0.0.1:9000"
export NGINX_LISTEN_PORT="${PORT:-8080}"
export FRAPPE_SITE_NAME_HEADER="${FRAPPE_SITE_NAME}"
export CLIENT_MAX_BODY_SIZE="${CLIENT_MAX_BODY_SIZE:-100m}"
export PROXY_READ_TIMEOUT="${PROXY_READ_TIMEOUT:-120}"

echo "Starting Nginx reverse proxy on port ${NGINX_LISTEN_PORT}..."
exec /usr/local/bin/nginx-entrypoint.sh
