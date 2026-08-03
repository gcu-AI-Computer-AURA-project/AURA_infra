#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/home/ec2-user/aura}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
SERVER_CONTAINER="${SERVER_CONTAINER:-aura-server}"
NGINX_CONTAINER="${NGINX_CONTAINER:-aura-nginx}"
DOMAIN_NAME="${DOMAIN_NAME:-api.dev-aura.r-e.kr}"
INFRA_SOURCE_DIR="${INFRA_SOURCE_DIR:-/home/ec2-user/source/AURA_infra}"
HEALTH_URL="${HEALTH_URL:-http://localhost/actuator/health}"
HEALTH_MAX_ATTEMPTS="${HEALTH_MAX_ATTEMPTS:-30}"
HEALTH_SLEEP_SECONDS="${HEALTH_SLEEP_SECONDS:-5}"
CERT_FILE="$DEPLOY_DIR/certbot/conf/live/$DOMAIN_NAME/fullchain.pem"
HTTP_CONF_SOURCE="$INFRA_SOURCE_DIR/nginx/conf.d/aura.conf"
HTTPS_CONF_SOURCE="$INFRA_SOURCE_DIR/nginx/conf.d/aura.https.conf.template"
ACTIVE_CONF_TARGET="$DEPLOY_DIR/nginx/conf.d/aura.conf"
HTTPS_CONF_TARGET="$DEPLOY_DIR/nginx/conf.d/aura.https.conf.template"
HTTPS_HEALTH_URL="${HTTPS_HEALTH_URL:-https://$DOMAIN_NAME/actuator/health}"
HTTPS_ENABLED=0

certificate_exists() {
	if [ -f "$CERT_FILE" ]; then
		return 0
	fi

	if command -v sudo >/dev/null 2>&1 && sudo -n test -f "$CERT_FILE" 2>/dev/null; then
		return 0
	fi

	return 1
}

active_conf_has_https() {
	[ -f "$ACTIVE_CONF_TARGET" ] && grep -q "listen 443 ssl" "$ACTIVE_CONF_TARGET"
}

apply_nginx_conf() {
	if certificate_exists; then
		cp "$HTTPS_CONF_SOURCE" "$ACTIVE_CONF_TARGET"
		HTTPS_ENABLED=1
		echo "HTTPS nginx config applied."
		return 0
	fi

	if active_conf_has_https; then
		HTTPS_ENABLED=1
		echo "Existing HTTPS nginx config preserved. Certificate file is not readable by the current user."
		return 0
	fi

	cp "$HTTP_CONF_SOURCE" "$ACTIVE_CONF_TARGET"
	HTTPS_ENABLED=0
	echo "HTTP bootstrap nginx config applied."
}

cd "$DEPLOY_DIR"

if [ -d "$INFRA_SOURCE_DIR" ]; then
	mkdir -p "$DEPLOY_DIR/nginx/conf.d"
	mkdir -p "$DEPLOY_DIR/scripts"
	mkdir -p "$DEPLOY_DIR/certbot/www"
	mkdir -p "$DEPLOY_DIR/certbot/conf"

	cp "$INFRA_SOURCE_DIR/docker-compose.prod.yml" "$DEPLOY_DIR/$COMPOSE_FILE"
	cp "$HTTPS_CONF_SOURCE" "$HTTPS_CONF_TARGET"
	apply_nginx_conf

	cp "$INFRA_SOURCE_DIR"/scripts/*.sh "$DEPLOY_DIR/scripts/"
	chmod +x "$DEPLOY_DIR"/scripts/*.sh
elif certificate_exists || active_conf_has_https; then
	HTTPS_ENABLED=1
fi

docker compose -f "$COMPOSE_FILE" config --quiet
docker compose -f "$COMPOSE_FILE" pull
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans
docker compose -f "$COMPOSE_FILE" ps
docker exec "$NGINX_CONTAINER" nginx -t
docker exec "$NGINX_CONTAINER" nginx -s reload

for attempt in $(seq 1 "$HEALTH_MAX_ATTEMPTS"); do
	if curl -fsS "$HEALTH_URL"; then
		if [ "$HTTPS_ENABLED" = "1" ]; then
			if ! docker exec "$NGINX_CONTAINER" nginx -T 2>/dev/null | grep -q "listen 443 ssl"; then
				echo "HTTPS nginx config is expected, but active nginx config does not listen on 443 ssl."
				exit 1
			fi

			curl -kfsS --resolve "$DOMAIN_NAME:443:127.0.0.1" "$HTTPS_HEALTH_URL"
		fi

		echo "Health check succeeded."
		docker image prune -af
		exit 0
	fi

	if [ "$attempt" -eq "$HEALTH_MAX_ATTEMPTS" ]; then
		echo "Health check failed after $HEALTH_MAX_ATTEMPTS attempts."
		docker compose -f "$COMPOSE_FILE" ps
		docker logs --tail=200 "$SERVER_CONTAINER" || true
		docker logs --tail=100 "$NGINX_CONTAINER" || true
		exit 1
	fi

	echo "Health check is not ready yet. retrying... ($attempt/$HEALTH_MAX_ATTEMPTS)"
	sleep "$HEALTH_SLEEP_SECONDS"
done
