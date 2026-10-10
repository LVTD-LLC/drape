# Drape

Native iPhone app. Prefer SwiftUI, SwiftData, PhotosUI, Vision, LocalAuthentication, Keychain, and URLSession. Deployment target iOS 17.6; build with a current stable Xcode. Keep the app useful offline.

- `project.yml` is the XcodeGen source; commit the generated Xcode project as well.
- Use normal ad-hoc simulator signing for builds/tests. `CODE_SIGNING_ALLOWED=NO` breaks simulator Keychain access. It is only appropriate for the explicitly unsigned device archive check.
- Never commit API keys, signing credentials, real wardrobe photos, or personal backups. The photo under `DrapeTests/Fixtures` is synthetic.
- Save source photos before processing. Preserve originals and user edits. AI results remain suggestions until accepted, and studio images require explicit selection.
- Every remote photo upload requires an explicit disclosed action (Ask AI or Add and ask AI); do not add a second upload modal or customer key setup. Do not put shared OpenRouter or R2 credentials in a mobile binary.
- No automatic paid retries. Keep model objects on the main actor, and do image work off the main actor.
- Test persistence by reopening the store and compare restored photo bytes. Retain in-memory ModelContainers throughout their tests.
- Do not add server accounts or cloud sync without implementing authentication, per-user authorization, data recovery, and a migration path. See `docs/ARCHITECTURE.md`.
- Before changing a shipped schema, add an explicit schema migration plan that retains the original model version.
- Run the Drape test scheme on an iPhone simulator. Camera, Vision quality, and Face ID still require physical-device checks before release.
