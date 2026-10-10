# Drape AI service

The private development backend uses Python, FastAPI, HTTPX, and Uvicorn in one Docker container. CapRover terminates HTTPS at `https://drape-ai.cr.lvtd.dev`. The iPhone uses URLSession. Photos pass through memory to OpenRouter; the service has no wardrobe database, photo storage, accounts, or sync.

## Run the iPhone app

1. Keep `OPENROUTER_API_KEY` and `DRAPE_DEVELOPMENT_TOKEN` in the ignored repo `.env`. The provider key belongs only on the server. The development token must match CapRover.
2. Run `python3 scripts/configure-development.py`. It creates the ignored `config/Development.local.xcconfig`, containing the service URL and development token, not the OpenRouter key.
3. Run the Debug Drape scheme from Xcode on an iPhone or simulator. No Settings key entry or local server is needed.

The revocable development token is embedded in private Debug builds. Anyone possessing such a build may extract it, so do not distribute these builds publicly. Release has neither a token nor an enabled API client. Before TestFlight/public release, replace this development mechanism with real user authentication or validated app attestation and durable per-user/device quotas. Do not simply copy the Debug settings to Release.

## Backend

`backend/requirements.txt` pins dependencies. The Docker build context is **backend/** and uses `backend/captain-definition`. Only explicitly listed source files enter the image; `.env` and local iPhone config never enter the build context or image.

CapRover app: `drape-ai`, one instance, container port 8000. Set `OPENROUTER_API_KEY`, `DRAPE_DEVELOPMENT_TOKEN` (at least 32 URL-safe characters), and `APP_REVISION` in CapRover environment settings. Enable base-domain HTTPS and force HTTPS. Drape's Nginx template limits bodies to 12 MB, disables request/response disk buffering, and allows 180 seconds for upstream responses. No host port is published.

The service authenticates before reading photos, permits only two fixed models and bounded generation settings, rejects external image URLs, limits bodies and responses, permits two concurrent AI requests, and allows 30 attempts per hour across the private development credential. The counter is in memory and resets on restart; this is a development throttle, not durable billing control. Run only one worker and one replica. Provider requests are never automatically retried. Raw provider errors and authorization values are not logged or returned to the app.

`GET /healthz` is public and returns service mode and revision. Paid endpoints require the development bearer credential. Rotate/revoke development access by replacing the token in CapRover and the ignored `.env`, then regenerating the Debug config and rebuilding.

## Verification

```sh
uv venv build/backend-venv
uv pip sync backend/requirements.txt --python build/backend-venv/bin/python
build/backend-venv/bin/python -m unittest discover -s backend -p 'test_*.py'
xcodebuild -project Drape.xcodeproj -scheme Drape \
  -destination 'platform=iOS Simulator,name=Drape iPhone 17 Pro' \
  -derivedDataPath build test
```

UI-test launches disable the AI endpoint, preventing accidental paid requests. A live smoke test must be explicit and use the synthetic fixture unless the user has confirmed uploading other photos. A health check alone does not verify OpenRouter or the app flow.

## Privacy and release

The Add to wardrobe / Finish preparing button is the explicit per-action upload confirmation. Nearby text explains the upload; there is no second modal or customer API-key setup. Originals are saved before requests, details fill automatically without replacing edits, and new studio images become the cover automatically. Save photos only remains available. Public privacy and App Store disclosures must describe Drape's gateway and OpenRouter processing before release.
