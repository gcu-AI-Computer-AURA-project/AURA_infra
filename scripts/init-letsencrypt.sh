#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/home/ec2-user/aura}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
DOMAIN_NAME="${DOMAIN_NAME:-api.dev-aura.r-e.kr}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
INFRA_SOURCE_DIR="${INFRA_SOURCE_DIR:-/home/ec2-user/source/AURA_infra}"
STAGING="${STAGING:-0}"
CERT_FILE="$DEPLOY_DIR/certbot/conf/live/$DOMAIN_NAME/fullchain.pem"

if [ -z "$LETSENCRYPT_EMAIL" ]; then
	echo "LETSENCRYPT_EMAIL is required."
	echo "example: LETSENCRYPT_EMAIL=you@example.com bash scripts/init-letsencrypt.sh"
	exit 1
fi

cd "$DEPLOY_DIR"

mkdir -p "$DEPLOY_DIR/nginx/conf.d"
mkdir -p "$DEPLOY_DIR/scripts"
mkdir -p "$DEPLOY_DIR/certbot/www"
mkdir -p "$DEPLOY_DIR/certbot/conf"

if [ -d "$INFRA_SOURCE_DIR" ]; then
	cp "$INFRA_SOURCE_DIR/docker-compose.prod.yml" "$DEPLOY_DIR/$COMPOSE_FILE"
	cp "$INFRA_SOURCE_DIR/nginx/conf.d/aura.conf" "$DEPLOY_DIR/nginx/conf.d/aura.conf"
	cp "$INFRA_SOURCE_DIR/nginx/conf.d/aura.https.conf.template" "$DEPLOY_DIR/nginx/conf.d/aura.https.conf.template"
fi

docker compose -f "$COMPOSE_FILE" config --quiet
docker compose -f "$COMPOSE_FILE" up -d aura-server nginx

if [ ! -f "$CERT_FILE" ]; then
	certbot_args=()

	if [ "$STAGING" = "1" ]; then
		certbot_args+=(--staging)
	fi

	docker compose -f "$COMPOSE_FILE" --profile certbot run --rm certbot certonly \
		--webroot \
		--webroot-path /var/www/certbot \
		--email "$LETSENCRYPT_EMAIL" \
		--agree-tos \
		--no-eff-email \
		-d "$DOMAIN_NAME" \
		"${certbot_args[@]}"
else
	echo "Existing certificate found: $CERT_FILE"
fi

cp "$DEPLOY_DIR/nginx/conf.d/aura.https.conf.template" "$DEPLOY_DIR/nginx/conf.d/aura.conf"
docker compose -f "$COMPOSE_FILE" up -d nginx
docker compose -f "$COMPOSE_FILE" exec -T nginx nginx -s reload

curl -fsS "https://$DOMAIN_NAME/actuator/health"
echo
echo "HTTPS setup completed: https://$DOMAIN_NAME"
