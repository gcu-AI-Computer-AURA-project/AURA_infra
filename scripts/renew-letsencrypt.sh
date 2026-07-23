#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/home/ec2-user/aura}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"

cd "$DEPLOY_DIR"

docker compose -f "$COMPOSE_FILE" --profile certbot run --rm certbot renew
docker compose -f "$COMPOSE_FILE" exec -T nginx nginx -s reload
