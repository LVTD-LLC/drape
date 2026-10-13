# Architecture and decisions

## First release

Drape is an iPhone app with a local SwiftData store. A garment owns a normalized whole-piece image, optional additional angles and label images, an optional on-device cutout, an optional generated studio image, and structured metadata. Large image data uses SwiftData external storage. A small thumbnail serves grids. Stable UUIDs identify garments and looks; deleting a garment removes its UUID from every look.

Photos are decoded to a maximum 1,800 pixels before storage. Re-encoding removes EXIF/location metadata. Vision runs in a detached task rather than blocking SwiftUI. Model instances remain on the main actor. The processing coordinator owns tasks independently of detail screen presentation and prevents concurrent processing of the same garment. It saves the source before work, marks interrupted work for explicit completion, checks cancellation/deletion before applying results, and saves analysis before attempting the optional image request. No paid request is automatically repeated.

AI results fill missing metadata automatically, preserving saved values and edits made during processing. New studio photos become the cover automatically; originals remain available in the carousel. Device cleanup may fail when a subject cannot be isolated or Vision resources are unavailable; the original remains usable. OCR text is exposed as reference text, not guessed size/care metadata.

AI calls use the private Rust/Axum gateway in `web/` on CapRover, which holds the operator's OpenRouter key. The app never reads that key. An ignored Debug-only xcconfig supplies the HTTPS gateway address and a separate revocable development bearer token. That token is extractable from private development builds and is not public-release authentication. Release builds have no enabled gateway or development token. The iPhone remains local-only. ShipRust adds a separate Postgres database and authenticated web-account scaffold, but signup and external integrations are not configured in production. There is no cloud wardrobe storage or mobile account linking. See [AI service](AI-SERVICE.md) for deployment, limits, and the required public-authentication follow-up. PhotosPicker requests access only to selected images. Camera access is requested when the user selects Camera. Optional Face ID/device-passcode protection covers the UI when the scene is inactive and locks on background entry.

SwiftData uses an explicit V1 → V2 → V3 migration plan; the shipped model layouts are retained as WardrobeSchemaV1 and WardrobeSchemaV2. Backup format is independently versioned, validates images and IDs, and merges missing objects transactionally. The 100 MB import/export limit is an explicit v1 constraint; large libraries should move to a streaming archive format before increasing this limit.

## Repository and service boundaries

`ios/` owns the Swift app, `android/` owns the native Kotlin / Compose client, and
`web/` owns the Rust API plus the generated web UI. Both future mobile clients
and the web catalog will share Rust business logic. No catalog frontend or
synchronization is implemented by the initial backend migration.

The web process serves the existing synchronous AI endpoints. A separate worker
process runs ShipRust jobs and cleanup against dedicated Postgres; it never
automatically retries AI work. The gateway accepts the iPhone's structured analysis
schema and prompts. See [AI service](AI-SERVICE.md) for topology and rollback.

## Cloud storage later

Apple permits external cloud storage. Cloudflare R2 is a viable object store, but the phone must never contain an R2 account credential. Add an authenticated API with Sign in with Apple token validation, per-user authorization, a metadata database, and short-lived presigned R2 uploads/downloads. Add per-record update timestamps, server revisions, tombstones, conflict handling, and idempotent sync operations before enabling synchronization. The current stable UUIDs and separated photo roles are compatible with that migration.

An Apple-only alternative is CloudKit with the user's iCloud account. Evaluate storage limits and SwiftData/CloudKit schema constraints (including unique attributes) before adopting it. Neither route should be presented as implemented in v1. The local catalogue should remain usable while offline or when sync fails.

## AI contracts

- Analysis: structured JSON with explicit categories, empty strings for unknown values, bounded output tokens, no sensitive person inference.
- Imagery: `/images`, one reference front photo, one output, faithful garment preservation prompt. Generation cannot guarantee exact fidelity; original comparison is part of the product.
- Failure: safe HTTP status descriptions; no raw provider response in user alerts; no authorization/request payload logging.
- Model selection: Drape owns fixed analysis and image choices; the gateway validates models and request limits. Provider errors are redacted and recoverable.
- Upload confirmation: the disclosed Add to wardrobe or Finish preparing action submits photos directly; no second modal or customer provider setup.

## Reference documentation

- [Swift](https://developer.apple.com/documentation/swift)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [Vision foreground masks](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest)
- [OpenRouter structured output](https://openrouter.ai/docs/guides/features/structured-outputs)
- [OpenRouter image generation](https://openrouter.ai/docs/guides/overview/multimodal/image-generation)

## Capture update: version 1 to version 2

`WardrobeSchemaV1` freezes the original Garment and Look properties and types, including external photo storage. `WardrobeMigrationPlan` uses a lightweight migration to V2, adding only nullable `extraPhotoData` (a JSON-encoded array of normalized photo bytes). Existing front, back, label, cutout, studio, details, UUIDs, favorites, and look membership are unchanged. A missing extra-photo field means no extra photos. The app opens the existing store with this plan; it never recreates a failed store. Migration tests reopen a file-backed V1 store in V2 and compare all photo bytes and metadata.

New capture stores the whole-piece photo in `front` and up to five additional angles or labels in `extraPhotoData`. Existing role-based photos remain in their original fields. Backup format V2 includes additional photos; the reader still accepts V1 backups. V1 readers reject V2 archives rather than silently discarding photos.

Add to wardrobe now explicitly discloses and starts analysis plus studio generation. Details fill automatically, preserving existing nonempty values and any edits made during processing; studio generation selects the new image as the cover. The detail screen uses a paged photo carousel, with originals retained. Save photos only remains available offline. Finish preparing is shown only for incomplete items, discloses uploads, and skips successful stages. There are no automatic paid retries or regeneration controls for completed pieces. Pending suggestions from older builds fill only empty fields at startup; previously saved edits and existing cover selections are retained.

## Richer item details: version 2 to version 3 migration plan

Before changing the shipped schema, preserve `WardrobeSchemaV1`, `WardrobeSchemaV2`, and their shared `ItemDetails` value layout unchanged. V3 adds only nullable `attributesData` to Garment: a versioned-by-schema JSON payload for tags, specific style, original price with currency/evidence/source, and visible condition with evidence/source. Nil means unknown, not zero price or perfect condition. Lightweight V1 → V2 → V3 migration preserves every original field, photo byte, ID, and look membership. Migration tests must open both shipped layouts, reopen V3, and compare source and generated photos, edits, and relationships.

Broad category and canonical item type form two taxonomy levels; optional specific style supplies a third. Legacy free-text subcategories remain stored and are mapped to known types for browsing where possible. Price is a reported original price, never an AI valuation: image extraction requires a legible amount, unambiguous currency, and supporting text. Condition estimates describe visible wear only and are labeled as estimates; unknown stays unknown. Manual edits take precedence, including edits made while processing.

Backup V3 includes attributes and remains able to import V1/V2 with empty attributes. Old apps reject V3 archives. Completed items cannot rerun analysis or studio generation, even if optional metadata is missing. Existing items can receive richer metadata through manual editing; new items collect it during their initial analysis. Finish preparing only processes unfinished stages. Tags are normalized and deduplicated; filtering combines category, type, tags, condition, and favorites. Price sorting groups currencies rather than comparing amounts across currencies without exchange rates.


## Android local wardrobe (schema v1)

Android uses Jetpack Compose with an app-owned coordinator, SQLite schema v1 for
item/look records, and private photo files. Android has an independent local wardrobe;
there is no cloud sync or iOS backup import. Originals are normalized to JPEG with EXIF
removed before storage/upload, preserving the stored source independently of studio
results. A disclosed action initiates each set of remote steps. Analysis is saved before
studio generation, manual edits take precedence, and interrupted work requires explicit
completion. Automatic HTTP retries and redirects are disabled for paid requests.

Android backup v1 exports records and photos in a bounded 100 MB JSON archive. Import
validates the full archive before committing missing records, remaps photo filenames,
and preserves existing records. Automatic OS cloud backup and device transfer are
disabled; users explicitly export/import through the system document picker. Optional
app locking uses Android device credentials. Shared provider secrets are never shipped;
only private debug builds may include the existing revocable gateway development token.

The first Android version omits Vision cutouts and cross-platform backup compatibility.
Its schema must be retained and explicitly migrated before future layout changes.
