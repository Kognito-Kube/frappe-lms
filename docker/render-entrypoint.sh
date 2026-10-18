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
printf "frappe\npayments\nlms\n" > /home/frappe/frappe-bench/sites/apps.txt
if [ ! -s /home/frappe/frappe-bench/sites/common_site_config.json ]; then
  echo "{}" > /home/frappe/frappe-bench/sites/common_site_config.json
fi

# 3. Resolve environment defaults
export DB_HOST="${DB_HOST:-mariadb}"
if [ -z "$DB_PORT" ] || [ "$DB_PORT" = "10000" ]; then
  export DB_PORT="3306"
fi
export REDIS_HOST="${REDIS_HOST:-redis}"
export REDIS_PORT="${REDIS_PORT:-6379}"
export REDIS_URL="${REDIS_URL:-redis://${REDIS_HOST}:${REDIS_PORT}}"
export FRAPPE_SITE_NAME="${FRAPPE_SITE_NAME:-lms.localhost}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-123}"

# Ensure MariaDB CLI tools do not fail SSL handshake over Render's internal network
printf "[client]\nskip-ssl\n" > /home/frappe/.my.cnf
chmod 600 /home/frappe/.my.cnf

# 4. Configure common_site_config.json atomically via jq
echo "Configuring common_site_config.json (DB=${DB_HOST}:${DB_PORT}, Site=${FRAPPE_SITE_NAME})..."
jq \
  --arg db_host "$DB_HOST" \
  --argjson db_port "$DB_PORT" \
  --arg redis_url "$REDIS_URL" \
  --arg default_site "$FRAPPE_SITE_NAME" \
  '. + {
    db_host: $db_host,
    db_port: $db_port,
    redis_cache: $redis_url,
    redis_queue: $redis_url,
    redis_socketio: $redis_url,
    socketio_port: 9000,
    default_site: $default_site,
    serve_default_site: true
  }' \
  /home/frappe/frappe-bench/sites/common_site_config.json > /home/frappe/frappe-bench/sites/common_site_config.json.tmp && \
  mv /home/frappe/frappe-bench/sites/common_site_config.json.tmp /home/frappe/frappe-bench/sites/common_site_config.json

# 5. Wait for MariaDB and Redis
echo "Waiting for MariaDB at ${DB_HOST}:${DB_PORT}..."
wait-for-it -t 180 "${DB_HOST}:${DB_PORT}"

until /home/frappe/frappe-bench/env/bin/python -c "import os, pymysql; conn = pymysql.connect(host=os.environ['DB_HOST'], port=int(os.environ['DB_PORT']), user='root', password=os.environ['MYSQL_ROOT_PASSWORD']); conn.close()" 2>/dev/null; do
  echo "Waiting for MariaDB to accept root connections..."
  sleep 3
done
echo "MariaDB connection verified!"

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
bench --site "${FRAPPE_SITE_NAME}" enable-scheduler || true

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
