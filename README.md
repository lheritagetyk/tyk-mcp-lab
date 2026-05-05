# Tyk MCP Lab


```
./up.sh mcp-gateway otel-jaeger
```

## What's included

| Deployment    | Purpose |
|---------------|---------|
| `tyk`         | Base Tyk stack (Dashboard, Gateway, Pump, Redis, Mongo) plus an `httpbin` sample upstream. Auto-bootstrapped. |
| `mcp-gateway` | Mock MCP server + MCP Inspector. Creates a `mock-mcp` REST proxy in the Dashboard so you can build the MCP demo live. |
| `otel-jaeger` | Jaeger all-in-one with OTLP receiver. Tyk Gateway is wired to export traces to it. |

Every other deployment from the upstream repo (analytics, federation, portal,
streams, sso, MDCB, etc.) has been removed.

## Prerequisites

- Docker with Docker Compose (4 GB RAM allocated is comfortable)
- `jq`
- A valid Tyk licence

## Quick start

**1. Configure local DNS entries**

```bash
sudo ./scripts/update-hosts.sh
```

This adds the three hostnames the lab needs to `/etc/hosts`:
`tyk-dashboard.localhost`, `tyk-portal.localhost`, `tyk-gateway.localhost`.

**2. Add your licence**

```bash
./scripts/update-env.sh DASHBOARD_LICENCE YOUR_LICENCE_KEY
```

**3. Launch the lab**

```bash
./up.sh mcp-gateway otel-jaeger
```

Wait for the `Tyk MCP lab initialisation process completed` banner.

**4. Access the services**

| Service        | URL |
|----------------|-----|
| Tyk Dashboard  | http://tyk-dashboard.localhost:3000 |
| Tyk Gateway    | http://tyk-gateway.localhost:8080 |
| Mock MCP       | http://localhost:7878 (health: `/health`) |
| MCP Inspector  | http://localhost:6274 |
| Jaeger UI      | http://localhost:16686 |

Dashboard credentials are printed by the bootstrap output.

## Sample APIs

Two APIs are available out of the box:

| API             | Listen path        | Upstream                     | Auth     |
|-----------------|--------------------|------------------------------|----------|
| Basic Open API  | `/basic-open-api/` | `httpbin` (mccutchen/go-httpbin, multi-arch) | Keyless  |
| mock-mcp        | `/mock-mcp/`       | `mcp-mock-server:7878`       | Keyless  |

The Dashboard's API explorer renders the full OpenAPI for **Basic Open API**
— five documented endpoints with parameter docs and response schemas:

```bash
# Plain GET — returns args/headers/origin/url
curl http://tyk-gateway.localhost:8080/basic-open-api/get

# POST with a JSON body — body comes back inside the json field
curl -X POST http://tyk-gateway.localhost:8080/basic-open-api/post \
  -H "Content-Type: application/json" \
  -d '{"hello":"world"}'

# Force a specific status code (great for testing error paths)
curl -i http://tyk-gateway.localhost:8080/basic-open-api/status/418

# Dump the headers Tyk forwarded upstream
curl http://tyk-gateway.localhost:8080/basic-open-api/headers

# Basic auth (challenges 401, then 200 with creds)
curl http://tyk-gateway.localhost:8080/basic-open-api/basic-auth/foo/bar
curl -u foo:bar http://tyk-gateway.localhost:8080/basic-open-api/basic-auth/foo/bar
```

Each request also shows up as a span in Jaeger at
http://localhost:16686 — pick `tyk-gateway` from the service dropdown.

## Common operations

```bash
./up.sh mcp-gateway otel-jaeger      # bring up the full lab
./up.sh                              # resume what's already bootstrapped
./down.sh                            # stop and remove everything
```

## Layout

```
.
├── up.sh                  Bootstrap entrypoint
├── down.sh                Teardown
├── docker-compose-command.sh
├── scripts/
│   ├── common.sh          Shared bootstrap helpers
│   ├── update-hosts.sh    Adds required hostnames to /etc/hosts
│   └── update-env.sh      Helper for setting .env values
└── deployments/
    ├── tyk/               Base Tyk stack + httpbin upstream
    │   └── data/tyk-dashboard/1/apis/basic-open-api.json
    │                      OAS spec for the Basic Open API sample
    ├── mcp-gateway/       Mock MCP server + Inspector + dashboard MCP proxy
    └── otel-jaeger/       Jaeger all-in-one
```

To add more sample APIs, drop additional OAS JSON files into
`deployments/tyk/data/tyk-dashboard/1/apis/`. The bootstrap iterates that
directory and creates each one in the Dashboard automatically.

## Provenance

Forked from `TykTechnologies/tyk-demo` (commit `8e377a51`). History was not
preserved — this is a fresh-history snapshot focused on the MCP lab path. For
any other deployment scenario, work from the upstream repo directly.
