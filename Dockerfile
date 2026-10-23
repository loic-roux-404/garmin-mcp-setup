# Ships the MCP server with its dependencies already resolved.
#
# The package tree comes from ./vendor, populated by install.sh on the build host.
# Doing the install at image-build time would make the build depend on the npm
# registry being reachable *and* on the daemon's clock being correct (a skewed
# clock makes npm reject the registry's TLS certificate). Copying a pre-built
# tree in avoids both.
FROM node:22-alpine

WORKDIR /app

COPY vendor/node_modules /app/node_modules

# Garmin issues a ~24h bearer token in exchange for the Personal API key; the
# server caches it here (mode 0600).
ENV HOME=/home/node

USER node

EXPOSE 8787

ENTRYPOINT ["node", "/app/node_modules/garmin-personal-mcp/dist/index.js", "--http", "8787"]
