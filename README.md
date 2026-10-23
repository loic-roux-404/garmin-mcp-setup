# garmin-mcp-setup

Runs [`garmin-personal-mcp`](https://github.com/Shape-Calendar/garmin-personal-mcp) in
Docker Compose, serving your own Garmin data over MCP (stateless Streamable HTTP).
Read-only, free, no Garmin subscription, no third-party host.

This wrapper is unofficial. The data comes from Garmin's **official Personal API** —
it is not a Garmin Connect credentials scraper.

## Files

| File | Purpose |
| --- | --- |
| `docker-compose.yml` | The service, port, env wiring, healthcheck |
| `Dockerfile` | `node:22-alpine` + the vendored package tree |
| `install.sh` | Populates `vendor/` from npm on the build host |
| `.env.example` | Template for the two secrets |
| `.dockerignore` | Keeps `.env` out of the build context |

## 1. Create the Garmin Personal API key

1. Open <https://connect.garmin.com/app/settings/personalApiToken>.
2. Choose an expiration period (one year maximum).
3. **Copy the key immediately** — Garmin shows it only once.

## 2. Create the bearer token

HTTP mode refuses to serve without one — the server answers `503` on every request.

```bash
openssl rand -hex 32
```

## 3. Configure

```bash
cp .env.example .env
chmod 600 .env
$EDITOR .env      # set GARMIN_PERSONAL_API_KEY and MCP_BEARER_TOKEN
```

## 4. Build and start

```bash
./install.sh              # npm install garmin-personal-mcp into vendor/
docker compose up -d
docker compose logs -f garmin-mcp
```

Expected log line:

```text
garmin-mcp  | garmin-personal-mcp listening on http://0.0.0.0:8787/mcp
```

## 5. Endpoint

```text
http://127.0.0.1:8787/mcp
```

Stateless Streamable HTTP with JSON responses; every request carries the bearer
token. There is no SSE transport and no `/health` route.

## 6. Register with an MCP client

Claude Code:

```bash
claude mcp add --transport http garmin http://127.0.0.1:8787/mcp \
  --header "Authorization: Bearer $(grep '^MCP_BEARER_TOKEN=' .env | cut -d= -f2-)"
```

Generic client config:

```json
{
  "mcpServers": {
    "garmin": {
      "type": "http",
      "url": "http://127.0.0.1:8787/mcp",
      "headers": { "Authorization": "Bearer <your MCP_BEARER_TOKEN>" }
    }
  }
}
```

Then ask:

```text
What was my sleep, HRV, Body Battery, and latest run from Garmin?
```

## Verify

```bash
# Unauthenticated: 401. Connection refused means it is not up.
curl -i http://127.0.0.1:8787/mcp

# Authenticated: JSON-RPC result with 25 tools.
curl -s -X POST http://127.0.0.1:8787/mcp \
  -H "Authorization: Bearer $(grep '^MCP_BEARER_TOKEN=' .env | cut -d= -f2-)" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

docker compose ps        # STATUS should reach (healthy)
```

Any request to another path (including `/health`) returns `404`; a request to `/mcp`
with a missing or wrong token returns `401`.

## Update

```bash
./install.sh 0.2.0        # bump the version
docker compose build
docker compose up -d
```

The version is pinned in two places: the argument to `install.sh` and the
`install.sh` default. Keep `Dockerfile` version-agnostic — it copies whatever
`vendor/` contains.

## Notes and gotchas

- **Transport is a CLI flag, not an env var.** `--http <port>` is the only way to
  leave stdio mode. `MCP_TRANSPORT` and `MCP_HTTP_PORT` do not exist; only `MCP_HOST`
  and `PORT` are read.
- **`MCP_BEARER_TOKEN` is mandatory** in HTTP mode.
- `MCP_HOST=0.0.0.0` is set *inside* the container; the published host port is
  `127.0.0.1` only.
- **The healthcheck is an authenticated `initialize` against `/mcp`**, accepting
  `200/400/405`. There is no dedicated health endpoint to probe.
- **Why the package is vendored instead of `npx`-installed at container start:**
  installing inside the container makes every start depend on the npm registry, and
  on the Docker host's clock being correct — a clock skew of even a few weeks makes
  npm reject the registry's TLS certificate as "not yet valid". `./install.sh` runs
  on the build host and the image just copies the result, so `docker compose up` is
  offline and deterministic.
- The Garmin key is exchanged for a ~24h JWT cached at `$HOME/.config`
  (`garmin-config` volume, mode `0600`). Upstream notes this cache can be shared with
  Garmin's own Python client.
- **Rotate** the Personal API key before it expires: update `.env`, then
  `docker compose up -d --force-recreate`.

## Security

- `.env` is gitignored, mode `600`, and excluded from the build context.
- `vendor/` is gitignored; `./install.sh` recreates it.
- The port binds to `127.0.0.1` only. Do not change that to `0.0.0.0` — for remote
  access put an authenticating TLS reverse proxy in front instead.
- Secrets are environment variables, so anyone who can run `docker inspect` on the
  Docker host can read them. That is inherent to Compose without a secrets backend.
