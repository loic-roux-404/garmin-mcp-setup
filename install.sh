#!/bin/sh
# Installs the MCP server into vendor/, which docker-compose.yml mounts read-only
# into the container at /app/node_modules.
#
# Why on the host: the install has to reach the npm registry, and doing it inside
# the container makes startup depend on the registry being up and on the Docker
# host's clock being correct. Doing it here keeps `docker compose up` hermetic.
set -eu

cd "$(dirname "$0")"

VERSION="${1:-0.1.1}"

if [ -f vendor/node_modules/garmin-personal-mcp/package.json ] &&
   grep -q "\"version\": \"$VERSION\"" vendor/node_modules/garmin-personal-mcp/package.json; then
    echo "garmin-personal-mcp@$VERSION already installed in vendor/"
    exit 0
fi

echo "Installing garmin-personal-mcp@$VERSION into vendor/ ..."
mkdir -p vendor
npm install --no-audit --no-fund --omit=dev "garmin-personal-mcp@$VERSION" --prefix vendor

echo "Installed. Start with: docker compose up -d"
