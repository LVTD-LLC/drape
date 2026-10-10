# Drape AI service

## Runtime and compatibility

`web/` is a ShipRust-generated Rust workspace (Axum, reqwest, SQLx/Postgres).
The existing iPhone endpoint remains `https://drape-ai.cr.lvtd.dev/api/v1/`.
`POST chat/completions` and `POST images` preserve the original JSON request,
response and error contracts. The iPhone still builds prompts and saves results.
The OpenRouter key stays on the server; photos pass through bounded memory only.

`web/app/src/ai.rs` owns the compatibility gateway. It verifies the private
`DRAPE_DEVELOPMENT_TOKEN` before reading photos, rejects browser Origin headers,
accepts embedded JPEGs only, and restricts requests to the two existing models and
settings. Limits remain 12 MB request, 40 MB response, two concurrent requests,
and 30 admitted attempts/hour. The in-memory counter resets on restart. Keep one
web replica. There are no paid retries or redirects. AI routes have their own body
and timeout policy, separate from ShipRust's small browser forms and account API.

`GET /healthz` returns status, private-development mode and build revision.
Responses carry `x-deployment-revision`. Health alone does not prove AI completion.

## Private iPhone setup

Keep `OPENROUTER_API_KEY` and `DRAPE_DEVELOPMENT_TOKEN` in the ignored root `.env`.
Run `python3 scripts/configure-development.py` to write
`ios/config/Development.local.xcconfig`. Only the gateway URL and development token
enter the Debug build; the provider key does not. Existing installed Debug builds
continue to use the same URL/token. Release still disables AI.

The development token is extractable from the private app. Public mobile release
requires proper authentication/attestation and durable per-user/device quotas.
The generated web account system does not automatically authenticate the iPhone.

## Production topology

| CapRover app | Role | Network / storage |
| --- | --- | --- |
| `drape-ai` | HTTP API and generated web frontend, `JOBS_WORKER=false` | Shared ingress + `drape-private`; no persistent wardrobe storage |
| `drape-worker` | Same image, `JOBS_WORKER=only` | `drape-private`; no public ingress |
| `drape-postgres` | Postgres 18, starter accounts and durable jobs | `drape-private`; `drape-postgres-data` volume |

Only these Drape apps are deployment targets. Other CapRover apps are excluded.
The worker runs starter jobs and cleanup, not paid AI requests. AI stays synchronous
for mobile compatibility. No wardrobe sync or catalog tables are introduced.

Web and worker use the same `DATABASE_URL`, `SITE_URL`, and port 8000. Only web needs
the OpenRouter key and development credential. `INDEXNOW_ENABLED=false` prevents
indexing this unfinished starter. Mail, Stripe, Sentry and PostHog credentials remain
unconfigured, so those integrations are inactive. Signup is disabled without email
verification configuration. Starter storage is compiled in but not used: no web users are provisioned. Before
enabling web signup/uploads, configure persistent object storage and recovery; the
existing gateway is a non-persistent CapRover app.

## GitHub deployment

`.github/workflows/deploy.yml` builds `web/Dockerfile` on GitHub Actions, pushes
`ghcr.io/lvtd-llc/drape:<commit>` and deploys the same image to both apps using a
pinned `caprover/deploy-from-github` action. CapRover must have GHCR pull access.
Repository secrets are `CAPROVER_SERVER`, `APP_TOKEN` (drape-ai), and
`WORKER_APP_TOKEN` (drape-worker). Both app tokens are required. `PRODUCTION_URL`
is `https://drape-ai.cr.lvtd.dev`. Deployments run on main and can be dispatched.
The pipeline verifies the public web revision after CapRover accepts the deployment;
operators also verify the worker's Docker health, role and image revision.

Run the Rust checks in `web/AGENTS.md` and the Drape iPhone simulator scheme.
Tests use local HTTP doubles and temporary databases, with no paid AI calls.
Explicit live validation uses only the synthetic cardigan fixture and one request
per AI stage; do not automatically retry a paid failure.

## Recovery and rollback

Before the Rust cutover, `drape-ai` used
`registry.cr.lvtd.dev:996/captain/img-captain-drape-ai:3` with port 8000 and no volumes.
The original provider key, development credential, TLS domain and Nginx upload
configuration are preserved. To revert just the AI gateway, deploy that retained
image to `drape-ai`; the iPhone URL remains unchanged. The old image reads
`APP_REVISION` rather than the Rust build revision. Preserve Postgres
volumes when rolling back; no data deletion is part of rollback.

Future schema changes require backups and forward-compatible migrations. Never
roll the Rust binary back across an incompatible applied database migration. The
initial Rust database is new and contains no migrated mobile wardrobe data.

To run that paid check through the actual iOS client (requires ignored Debug config):

```sh
python3 scripts/test-live-gateway.py --simulator IPHONE_SIMULATOR_UUID --confirm-paid-requests
```

It opts a single XCTest into the live service, verifies both decoded outputs, and
never retries. Ordinary simulator/CI runs skip this test. The private build log
stays under ignored `build/rust-migration/`.
