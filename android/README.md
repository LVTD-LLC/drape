# Drape for Android

Native Kotlin / Jetpack Compose wardrobe app. Android 9+ (API 28), compiled and
targeted for Android 16 (API 36). Uses the existing Rust AI gateway.

## Run

Install JDK 17 and Android SDK 36, then open this directory in Android Studio.
Create an ignored `local.properties` containing `sdk.dir=/path/to/Android/sdk`.

```sh
./gradlew assembleDebug
adb -s DEVICE_SERIAL install -r app/build/outputs/apk/debug/app-debug.apk
adb -s DEVICE_SERIAL shell am start -n dev.lvtd.drape/.MainActivity
```

Private AI preparation reads `ai.url` and `ai.token` from ignored
`development.properties`. Use the existing revocable Drape development gateway
credential, never an OpenRouter key. `python3 ../scripts/configure-android.py`
copies the configured private iOS gateway settings without printing credentials.
Release builds contain neither gateway access nor a development token. This private
build is not ready for public distribution; public mobile authentication is pending.

## Features

- Camera and Android photo picker; whole-piece photo plus up to five details.
- Local original photos, editable metadata, favorites, category/search filters,
  sorting, and saved looks. No server accounts or wardrobe sync.
- Explicitly disclosed AI analysis and studio generation. Save photos only works
  offline. Completed steps are retained; paid requests are never automatically retried.
- Original/studio comparison and cover selection. Edits made during processing win.
- Device-credential lock, explicit local export/import, and no automatic OS backup.
- Android backup format v1, 100 MB maximum; merges missing records and validates
  photo data before importing. It is not compatible with iOS backup files yet.

## Verify

Run instrumentation only on a dedicated emulator; it creates and removes synthetic
wardrobe items. The fixture is copied from the synthetic iOS test fixture.

```sh
./gradlew lintDebug assembleDebug assembleDebugAndroidTest
ANDROID_SERIAL=emulator-5554 ./gradlew connectedDebugAndroidTest
```

The normal suite makes no paid requests. Explicit live gateway verification makes
one analysis and one studio request with the synthetic fixture:

```sh
adb -s emulator-5554 shell am instrument -w \
  -e class dev.lvtd.drape.GatewaySmokeTest -e paidSmoke true \
  dev.lvtd.drape.test/androidx.test.runner.AndroidJUnitRunner
```

Verify camera capture, photo selection, device lock, background/relaunch, and offline
use on the Samsung device before relying on it for a large wardrobe. Android does not
yet have iOS Vision cutouts or iOS backup import. Camera is delegated to the installed
camera app and uses a scoped FileProvider; no broad photo-library permission is needed.

## Persistence

SQLite schema v1 stores item/look JSON and stable UUIDs. Normalized, EXIF-stripped
JPEGs live in private app files and are saved before a record or any remote request.
Photo work and disk/network I/O run off the UI thread. UI state and coordination run
on the main thread. A mutex serializes database mutations. Future schema changes must
retain schema v1 and add an explicit non-destructive migration.

Preparation survives activity recreation, but not process termination. Interrupted
work is marked unfinished on the next launch and requires Finish preparing. A process
kill between a paid response and local persistence cannot guarantee deduplication;
server-side request idempotency would be needed for that guarantee.
