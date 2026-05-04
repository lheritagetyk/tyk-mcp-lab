# Tyk MCP Lab

A slimmed-down fork of [TykTechnologies/tyk-demo](https://github.com/TykTechnologies/tyk-demo)
trimmed to only what's needed to run the **MCP Gateway + OpenTelemetry/Jaeger**
lab.

```
./up.sh mcp-gateway otel-jaeger
```

## What's included

| Deployment    | Purpose |
|---------------|---------|
| `tyk`         | Base Tyk stack (Dashboard, Gateway, Pump, Redis, Mongo, supporting upstreams). Auto-bootstrapped. |
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

This adds the four hostnames the lab needs to `/etc/hosts`:
`tyk-dashboard.localhost`, `tyk-portal.localhost`, `tyk-gateway.localhost`,
`tyk-gateway-2.localhost`.

**2. Add your licence**

```bash
./scripts/update-env.sh DASHBOARD_LICENCE YOUR_LICENCE_KEY
```

**3. Launch the lab**

```bash
./up.sh mcp-gateway otel-jaeger
```

Wait for the `Tyk MCP lab initialisation process completed` banner. First run
builds Go plugins (5–10 minutes); subsequent runs are cached.

**4. Access the services**

| Service        | URL |
|----------------|-----|
| Tyk Dashboard  | http://tyk-dashboard.localhost:3000 |
| Tyk Gateway    | http://tyk-gateway.localhost:8080 |
| Mock MCP       | http://localhost:7878 (health: `/health`) |
| MCP Inspector  | http://localhost:6274 |
| Jaeger UI      | http://localhost:16686 |

Dashboard credentials are printed by the bootstrap output.

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
    ├── tyk/               Base Tyk stack
    ├── mcp-gateway/       Mock MCP server + Inspector + dashboard MCP proxy
    └── otel-jaeger/       Jaeger all-in-one
```

## Provenance

Forked from `TykTechnologies/tyk-demo` (commit `8e377a51`). History was not
preserved — this is a fresh-history snapshot focused on the MCP lab path. For
any other deployment scenario, work from the upstream repo directly.
