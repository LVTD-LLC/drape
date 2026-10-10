# Architecture and decisions

## First release

Drape is an iPhone app with a local SwiftData store. A garment owns normalized front, optional back and label images, an optional on-device cutout, an optional generated studio image, and structured metadata. Large image data uses SwiftData external storage. A small thumbnail serves grids. Stable UUIDs identify garments and looks; deleting a garment removes its UUID from every look.

Photos are decoded to a maximum 1,800 pixels before storage. Re-encoding removes EXIF/location metadata. Vision runs in a detached task rather than blocking SwiftUI. Model instances remain on the main actor. The processing coordinator owns tasks independently of detail screen presentation and prevents concurrent processing of the same garment. It saves the source before work, marks interrupted work for explicit retry, checks cancellation/deletion before applying results, and saves analysis before attempting the optional image request. No paid request is automatically repeated.

AI suggestions do not overwrite user metadata. Applying reviewed suggestions is explicit. Studio photos remain previews until selected. Device cleanup may fail when a subject cannot be isolated or Vision resources are unavailable; the original remains usable. OCR text is exposed as reference text, not guessed size/care metadata.

AI calls use the private Python/FastAPI gateway on CapRover, which holds the operator's OpenRouter key. The app never reads that key. An ignored Debug-only xcconfig supplies the HTTPS gateway address and a separate revocable development bearer token. That token is extractable from private development builds and is not public-release authentication. Release builds have no enabled gateway or development token. No account database, cloud wardrobe storage, analytics SDK, or advertising SDK is added. See [AI service](AI-SERVICE.md) for deployment, limits, and the required public-authentication follow-up. PhotosPicker requests access only to selected images. Camera access is requested when the user selects Camera. Optional Face ID/device-passcode protection covers the UI when the scene is inactive and locks on background entry.

SwiftData's initial schema is version 1 in practice; before any shipping schema changes, introduce explicit VersionedSchema and SchemaMigrationPlan using this exact model layout as the initial version. Backup format is independently versioned, validates images and IDs, and merges missing objects transactionally. The 100 MB import/export limit is an explicit v1 constraint; large libraries should move to a streaming archive format before increasing this limit.

## Cloud storage later

Apple permits external cloud storage. Cloudflare R2 is a viable object store, but the phone must never contain an R2 account credential. Add an authenticated API with Sign in with Apple token validation, per-user authorization, a metadata database, and short-lived presigned R2 uploads/downloads. Add per-record update timestamps, server revisions, tombstones, conflict handling, and idempotent sync operations before enabling synchronization. The current stable UUIDs and separated photo roles are compatible with that migration.

An Apple-only alternative is CloudKit with the user's iCloud account. Evaluate storage limits and SwiftData/CloudKit schema constraints (including unique attributes) before adopting it. Neither route should be presented as implemented in v1. The local catalogue should remain usable while offline or when sync fails.

## AI contracts

- Analysis: structured JSON with explicit categories, empty strings for unknown values, bounded output tokens, no sensitive person inference.
- Imagery: `/images`, one reference front photo, one output, faithful garment preservation prompt. Generation cannot guarantee exact fidelity; original comparison is part of the product.
- Failure: safe HTTP status descriptions; no raw provider response in user alerts; no authorization/request payload logging.
- Model selection: Drape owns fixed analysis and image choices; the gateway validates models and request limits. Provider errors are redacted and recoverable.
- Upload confirmation: the disclosed Ask AI or Add and ask AI action submits photos directly; no second modal or customer provider setup.

## Reference documentation

- [Swift](https://developer.apple.com/documentation/swift)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [Vision foreground masks](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest)
- [OpenRouter structured output](https://openrouter.ai/docs/guides/features/structured-outputs)
- [OpenRouter image generation](https://openrouter.ai/docs/guides/overview/multimodal/image-generation)
