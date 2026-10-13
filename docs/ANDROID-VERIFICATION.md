# Android first-build verification — 2026-10-13

Environment: dedicated `Drape_API_36` emulator, Android 16 / API 36, arm64.
Physical Samsung Galaxy S22 Ultra / One UI 8 verification was deferred at the user's
request. No device installation is claimed.

## Passed

- Debug and release APK builds; Android lint has no errors (dependency-update and
  API-modernization warnings remain).
- Six non-paid instrumentation tests: offline UI add/edit/favorite/delete; backup
  export/import/duplicate merge with original byte comparison; close/reopen store with
  source and studio byte checks plus look relationships; edit-safe metadata merging;
  evidence/value consistency; invalid file/image rejection; outgoing content type and
  simulated network failure. Some tests cover multiple assertions/flows.
- One explicitly enabled live test through the actual Add to wardrobe UI, using only
  the synthetic cardigan fixture: analysis and studio generation completed in 21.285 s
  total test time. Originals matched byte-for-byte, generated cover was selected, and
  attempting to prepare the completed piece was a no-op.
- Force-stop and cold launch retained the generated wardrobe piece.
- Emulator camera launch, shutter and return of a captured photo to Drape; native
  Android photo picker opens successfully. The temporary camera draft was discarded.
- Private development credential absent from all source files and every entry in the
  unsigned release APK. Private debug APK intentionally uses the revocable gateway
  development token, as the existing private iPhone build does.

The first live attempt was rejected before upstream processing: OkHttp's String
request body added `charset=utf-8`, while the gateway requires exactly
`application/json`. The Android client now submits UTF-8 bytes with that exact media
value. No backend or iPhone API contract was changed. Automatic paid retries remain
explicitly disabled.

## Remaining device/release checks

- Samsung camera, photo picker, app lock, lifecycle/background behavior and usability.
- Public mobile authentication before distributing AI-enabled builds.
- Android/iOS backup interoperability and Android on-device cutouts are not implemented.
- The existing iOS project and backend were not changed or retested by this Android work.

Screenshots in `docs/evidence/android-wardrobe.png` contain only the synthetic fixture.
The emulator keeps that one synthetic item for review. Local build products and private
configuration are ignored by Git.
