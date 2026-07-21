#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/home/ec2-user/aura}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
SERVER_CONTAINER="${SERVER_CONTAINER:-aura-server}"
NGINX_CONTAINER="${NGINX_CONTAINER:-aura-nginx}"
HEALTH_URL="${HEALTH_URL:-http://localhost/actuator/health}"
HEALTH_MAX_ATTEMPTS="${HEALTH_MAX_ATTEMPTS:-30}"
HEALTH_SLEEP_SECONDS="${HEALTH_SLEEP_SECONDS:-5}"

cd "$DEPLOY_DIR"

docker compose -f "$COMPOSE_FILE" config --quiet
docker compose -f "$COMPOSE_FILE" pull
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans
docker compose -f "$COMPOSE_FILE" ps

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
