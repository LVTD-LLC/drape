# Native Android

Use Kotlin, Jetpack Compose, Android photo picker and scoped camera capture. Keep the
wardrobe useful offline. Read the root AGENTS.md and docs/ARCHITECTURE.md.

- Do image, database, and network work off the main thread; coordinate UI state on main.
- Save source photos before AI work. Preserve originals, edits and successful stages.
- Upload only after disclosed Add to wardrobe or Finish preparing actions. Never add
  automatic paid retries or regenerate completed items.
- Never commit development.properties, local.properties, credentials, real photos, APKs,
  databases or user backups. Release AI access must remain disabled until public auth.
- Preserve SQLite schema v1 and add explicit migrations before changing shipped data.
- Verify persistence by closing/reopening the store and comparing original photo bytes.
- Run lint and instrumentation on a dedicated emulator. Paid gateway tests require the
  explicit paidSmoke argument and use only the synthetic test fixture.
- Install with adb install -r to preserve data. Never clear or uninstall a user's app
  without explicit authorization. Camera, credentials, and Samsung behavior need device checks.
