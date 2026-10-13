# Drape

A private wardrobe for the clothes you already love.

| Directory | Purpose |
| --- | --- |
| `ios/` | Native SwiftUI iPhone app, SwiftData catalog, XcodeGen project and tests |
| `android/` | Native Kotlin / Compose Android app, local wardrobe and device tests |
| `web/` | ShipRust-generated Rust workspace: Axum API and starter web UI, Postgres, worker |
| `docs/` | Shared architecture, deployment, privacy, and release documentation |
| `scripts/` | Development configuration and explicit integration checks |

## iPhone

Open `ios/Drape.xcodeproj`. The deployment target is iOS 17.6. For private AI
access, run `python3 scripts/configure-development.py` using the existing ignored
root `.env`. The gateway URL and development token are unchanged by the Rust migration.
Release AI remains disabled pending public mobile authentication.

```sh
xcodebuild -project ios/Drape.xcodeproj -scheme Drape \
  -destination 'platform=iOS Simulator,name=Drape iPhone 17 Pro' \
  -derivedDataPath build/ios test
```

Use normal simulator signing. `ios/project.yml` is the XcodeGen source; regenerate
from `ios/` when changing it. Camera, Vision quality and Face ID require a physical device.

Add up to six photos, then tap **Add to wardrobe** after reading the nearby upload
disclosure. Photos save first; AI details and a studio cover appear as processing
finishes. **Save photos only** works offline. **Finish preparing** explicitly retries
unfinished stages. Originals and user edits are preserved. Export backups through Files.

## Android

Open `android/` in Android Studio. See [Android setup and verification](android/README.md).
The native app uses the same AI gateway and keeps its wardrobe locally. Android 9+;
target Android 16. Private development AI access is configured separately.

## Rust web and backend

Generated through ShipRust with every offered feature enabled. Generator provenance
is in `web/.shiprust.toml`; see `web/README.md` and `web/AGENTS.md` for the starter.
Credentials for optional integrations are configured separately; generating code does
not activate billing, mail, telemetry or cloud storage.

```sh
cd web
docker compose -p drape-web up -d
cp .env.example .env  # only when no local .env already exists
cargo sqlx migrate run
cargo run
```

The isolated local database listens on `127.0.0.1:55434`. The development HTTP
server defaults to port 3000. Production uses port 8000 to preserve the existing gateway.

The Rust service implements the existing `/api/v1/chat/completions` and
`/api/v1/images` contract using reqwest. The iPhone's Swift client and prompts are
unchanged. No wardrobe records or uploaded AI photos are stored on the server.
The generated frontend is a scaffold, not a synchronized web wardrobe.

Production has separate `drape-ai` web, `drape-worker`, and `drape-postgres` services.
GitHub Actions builds one image and deploys web and worker through
`caprover/deploy-from-github`. See [deployment and rollback](docs/AI-SERVICE.md).

A future synchronized catalog for Android, iOS and web would share an authenticated API. That
requires explicit account linking, per-user authorization, recovery, and sync
migration work before mobile data is uploaded. See [architecture](docs/ARCHITECTURE.md).
