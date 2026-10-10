# TestFlight and App Store handoff

## Product scope

Native iPhone app, iOS 17.6 or newer, compiled with the installed Xcode 26.5 SDK. Local catalogue, capture/import, local image isolation and label OCR, optional OpenRouter AI, editable details, favorite/search/filter/group, manual saved outfits, Face ID/device-passcode lock, and export/restore.

Not implemented: server accounts, cross-device sync, managed/shared AI billing, virtual try-on, or AI outfit generation. The user supplies an OpenRouter key for optional remote processing. No shared key belongs in a distributed binary.

## Before TestFlight

1. Open `Drape.xcodeproj`, select Drape → Signing & Capabilities, and choose the intended Apple Developer team. Confirm the bundle ID `dev.lvtd.drape` is available for that team.
2. Register an App Store Connect app for the bundle ID. Choose the final seller, age rating, and availability.
3. Run the app on a physical iPhone. Verify camera permission granted and denied, front-only capture, three-photo capture, rotation/orientation of photos, real garment segmentation, label OCR, Face ID/passcode lock, background/foreground, offline add/edit, and deletion.
4. Use a funded OpenRouter key on the phone. Test analysis and studio generation, a wrong key, exhausted credits, request cancellation/interruption, and one non-default model. Compare output with the original clothing. AI is a suggestion, not an authenticity guarantee.
5. Export actual data, terminate/relaunch, restore into a clean installation, and compare item details/photos and look membership. Exports contain private photos; store carefully.
6. Archive using Product → Archive on Any iOS Device. In Organizer, validate and distribute to App Store Connect. Select the correct team and let Xcode manage signing. Increment `CURRENT_PROJECT_VERSION` for each upload.
7. After App Store Connect processing, add an internal tester. External TestFlight distribution requires beta review. Do not claim an archive/upload succeeded until Organizer/App Store Connect confirms it.

Command-line unsigned archive for build verification:

```sh
xcodebuild -project Drape.xcodeproj -scheme Drape -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Drape.xcarchive \
  archive CODE_SIGNING_ALLOWED=NO
```

This archive is **not** installable or uploadable without distribution signing. For signed archives use your configured team and approved provisioning; do not commit credentials.

## Before App Store review

- Publish the completed privacy policy and a working support URL under the operator's control. The in-app privacy explanation is already included.
- Complete App Privacy answers accurately for photo transfer to third-party AI, including OpenRouter/model-provider retention. The bundled privacy manifest documents required-reason UserDefaults access and no app tracking; it does not replace App Store Connect privacy answers or provider policy review.
- Confirm whether the app's optional user-supplied API-key experience is appropriate for the intended public audience and review access. Provide reviewers a safe funded test configuration through App Store Connect review notes if necessary; never hardcode it.
- Supply genuine screenshots from the app for the required device sizes, description, subtitle, keywords, copyright, age rating, and review notes.
- Test VoiceOver, larger text sizes, light/dark appearance, small iPhone layout, and system photo picker accessibility.
- Check current [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/) at submission. Store acceptance cannot be guaranteed by a successful build.

## Suggested metadata

**Name:** Drape — Your Wardrobe

**Subtitle:** Your clothes, beautifully kept

**Description:**
Give the clothes you already love a home of their own. Photograph a piece, add its details, and build a wardrobe you can browse at a glance. Find favorites, search by color or brand, and save pieces together as looks for another day.

Drape keeps your wardrobe on your iPhone. Optional AI through your own OpenRouter account can suggest details and create studio-style photos. You review the results and keep the originals. Export a backup whenever you need one.

**Review notes:**
No Drape account is required. The catalogue, photo import, camera, local processing, editing, and saved looks work without OpenRouter. AI is optional and requires a user-supplied OpenRouter API key; every photo upload requires confirmation. AI-generated photos are labeled and are used as catalogue photos only after the user opts in. No purchases are made within Drape.
