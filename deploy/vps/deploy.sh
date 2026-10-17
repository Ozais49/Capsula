#!/usr/bin/env bash
# Updates the API to a version without downtime: restarts one container at a
# time and waits for it to answer before moving on to the other.
#
#   ./deploy.sh 1.2.0      (or "latest")
#
# Run on the server from /opt/capsula. The API workflow runs it on each release.
set -euo pipefail
cd "$(dirname "$0")"

version="${1:?usage: deploy.sh <version>}"

if [ ! -f .env ]; then echo ".env is missing (see env.example)" >&2; exit 1; fi
if [ ! -f secrets/service-account.json ]; then
  echo "secrets/service-account.json is missing" >&2; exit 1
fi

# Remember the version, so a reboot or "docker compose up" keeps it.
if grep -q '^API_VERSION=' .env; then
  sed -i "s/^API_VERSION=.*/API_VERSION=${version}/" .env
else
  echo "API_VERSION=${version}" >> .env
fi

docker compose pull api1 api2 caddy
# First deploy: start everything.
docker compose up -d caddy

healthy() {
  docker compose exec -T caddy wget -q -T 3 -O /dev/null "http://$1:8787/v1/health"
}

for service in api1 api2; do
  echo "Updating ${service}..."
  docker compose up -d --no-deps --force-recreate "$service"
  for _ in $(seq 1 30); do
    if healthy "$service"; then echo "${service} is up"; continue 2; fi
    sleep 2
  done
  echo "${service} didn't come up; its logs:" >&2
  docker compose logs --tail 50 "$service" >&2
  exit 1
done

docker image prune -f >/dev/null
echo "Capsula API ${version} is running."
