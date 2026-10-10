# Drape

A private wardrobe for the clothes you already love. A native iPhone app built with Swift 6, SwiftUI, SwiftData, PhotosUI, Vision, and Keychain. No third-party iOS runtime dependencies.

## Run

Open `Drape.xcodeproj` in Xcode 26.5 or newer, select the **Drape** scheme, choose an iPhone simulator, and run. The deployment target is iOS 17.6 (including iOS 17.6.1); the app builds against the installed SDK and adopts native iOS 26 controls on newer devices. Camera capture and device authentication need an actual iPhone for full verification.

```sh
xcodebuild -project Drape.xcodeproj -scheme Drape \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test
```

The checked-in Xcode project is ready to open. If changing project structure, install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and run `xcodegen generate`; `project.yml` is its source of truth.

For an iPhone, select your Apple Developer team in **Signing & Capabilities** and use a unique bundle identifier if `dev.lvtd.drape` is unavailable. Never commit signing certificates, profiles, API keys, or personal wardrobe exports.

For hosted AI in a private Debug build, run `python3 scripts/configure-development.py` first; see [AI service setup](docs/AI-SERVICE.md). Release AI remains disabled until public authentication is implemented.

## Use

1. Create your wardrobe. Add a front photo with the camera or photo picker. Back and label photos are optional.
2. Name or categorize the piece, then save. The app keeps the photos first and attempts on-device background removal and label OCR.
3. Edit any detail, mark favorites, search by description, and filter or group by clothing type.
4. Use **Ask AI** on a piece. Settings can also enable **Add and ask AI** and optional studio photos. No customer API key or provider setup is required.
5. The AI button submits the photos as explained beside it. Review suggestions before saving. A generated studio photo is available for comparison and becomes the catalogue photo only if you enable it.
6. Select pieces in **Looks** to save an outfit. Export a wardrobe backup to Files and restore it later when moving phones.

The app works offline without AI. There is no login, server account, or cross-device sync in v1. Optional device authentication protects the local wardrobe. Local photos may be included in the user's device backup depending on system settings; an explicit export is the portable backup.

## AI behavior

- Defaults: GPT-6 Luna (`openai/gpt-6-luna`) for analysis and Seedream 5.0 Flash (`bytedance-seed/seedream-5-0-flash`) for studio photos at 1K, 3:4. Existing Gemini defaults are updated once; custom model choices are preserved.
- Analysis uses `/api/v1/chat/completions` with a strict JSON schema. Unknown label-derived fields stay empty. The app stores suggestions separately from saved user edits.
- Studio photos use `/api/v1/images` with the original front photo as an input reference. Originals are never replaced. Generative results may change clothing details.
- Drape manages the model choices on its Python/FastAPI service. See [AI service setup](docs/AI-SERVICE.md) for the private CapRover development deployment and iPhone build configuration.
- The app sends normalized JPEGs without EXIF/GPS metadata. The OpenRouter key stays on the backend. Tapping Ask AI or Add and ask AI confirms each upload. Analysis requests disallow providers that collect data; image generation follows the selected provider's policy.
- No automatic paid retry. Interrupted work is marked for manual retry on next launch. Keep Drape open during processing.

For an explicit paid integration smoke test using the synthetic test image:

```sh
# OPENROUTER_API_KEY must already be set in your shell.
python3 scripts/verify-openrouter.py          # one analysis request
python3 scripts/verify-openrouter.py --studio # one analysis and one image request
```

Results are written under ignored `build/openrouter-smoke/`. The key is never printed or bundled. The synthetic fixture was generated for this project and contains no personal photos.

## Structure

- `Drape/App`: lifecycle, onboarding, and device lock.
- `Drape/Models`: garments, editable metadata, and saved looks.
- `Drape/Services`: local image processing, OpenRouter, processing lifecycle, backups, and Keychain.
- `Drape/Views`: native screens and capture components.
- `DrapeTests`, `DrapeUITests`: persistence, backup validation, response parsing, and user flows.
- `docs`: architecture, privacy policy draft, release steps, and verification evidence.

See [release steps](docs/RELEASE.md) for TestFlight and App Store requirements and [architecture](docs/ARCHITECTURE.md) for the future sync path.
