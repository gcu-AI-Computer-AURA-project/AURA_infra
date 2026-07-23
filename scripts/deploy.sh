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

cd "$DEPLOY_DIR"

if [ -d "$INFRA_SOURCE_DIR" ]; then
	mkdir -p "$DEPLOY_DIR/nginx/conf.d"
	mkdir -p "$DEPLOY_DIR/scripts"
	mkdir -p "$DEPLOY_DIR/certbot/www"
	mkdir -p "$DEPLOY_DIR/certbot/conf"

	cp "$INFRA_SOURCE_DIR/docker-compose.prod.yml" "$DEPLOY_DIR/$COMPOSE_FILE"
	cp "$INFRA_SOURCE_DIR/nginx/conf.d/aura.https.conf.template" "$DEPLOY_DIR/nginx/conf.d/aura.https.conf.template"

	if [ -f "$CERT_FILE" ]; then
		cp "$INFRA_SOURCE_DIR/nginx/conf.d/aura.https.conf.template" "$DEPLOY_DIR/nginx/conf.d/aura.conf"
	else
		cp "$INFRA_SOURCE_DIR/nginx/conf.d/aura.conf" "$DEPLOY_DIR/nginx/conf.d/aura.conf"
	fi

	cp "$INFRA_SOURCE_DIR"/scripts/*.sh "$DEPLOY_DIR/scripts/"
	chmod +x "$DEPLOY_DIR"/scripts/*.sh
fi

docker compose -f "$COMPOSE_FILE" config --quiet
docker compose -f "$COMPOSE_FILE" pull
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans
docker compose -f "$COMPOSE_FILE" ps
docker compose -f "$COMPOSE_FILE" exec -T "$NGINX_CONTAINER" nginx -t
docker compose -f "$COMPOSE_FILE" exec -T "$NGINX_CONTAINER" nginx -s reload

for attempt in $(seq 1 "$HEALTH_MAX_ATTEMPTS"); do
	if curl -fsS "$HEALTH_URL"; then
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
