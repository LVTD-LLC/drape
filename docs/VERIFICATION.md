# Verification — 9 October 2026

## Confirmed locally

- Xcode 26.5 (17F42), Swift 6.3.2, iOS 26.5 SDK, deployment target iOS 18.
- Signed simulator test suite on iPhone 17 Pro / iOS 26.5 (23F77): **16 passed, 0 failed, 0 skipped**. Machine-readable results: `evidence/test-summary.json`. Full local result bundle: `build/SignedTests.xcresult` (not committed).
- Release archive build: **ARCHIVE SUCCEEDED**, `build/Drape.xcarchive`. This is deliberately unsigned and not an App Store upload.
- On iOS 26.2, manually completed onboarding, imported a synthetic cardigan through Apple's photo picker, named/categorized/saved it, relaunched the app with the piece preserved, connected OpenRouter via Keychain, enabled studio generation, confirmed the upload, reviewed AI details, saved them, and selected the studio image for the catalogue.
- Actual app AI calls used `google/gemini-2.5-flash` and `google/gemini-2.5-flash-image`. Both completed. The front-only item yielded blank brand, size, fiber composition, and care fields; inferred color, garment type, pattern, season, and notes were shown for review. Originals and saved edits were not silently replaced.
- A separate paid API smoke check completed both endpoints. Recorded cost for that pair: $0.0397692. This cost does not include the later in-app verification requests. See `evidence/openrouter-analysis.json`, `evidence/openrouter-studio-summary.json`, and `evidence/cardigan-studio.png`.
- The temporary OpenRouter key was removed from the simulator after testing. No shared key is in the repository or archive.
- Larger-text onboarding uses a scroll view; verified the largest accessibility text setting renders expanded content. Full VoiceOver and all-screen large-text review remain physical-device release checks.

## Automated coverage

1. Keychain create/read/update/delete in a unique test service.
2. Structured AI response decoding and malformed/missing response rejection.
3. Invalid image response rejection.
4. Model capability filtering.
5. Missing API key handling before network activity.
6. Authenticated request endpoint/header and typed result.
7. Rate-limit error mapping without exposing raw provider text.
8. Invalid backup version, corrupt photo, and duplicate ID rejection.
9. Backup/restore retains all photo bytes, metadata, favorites, and look membership; repeated restore keeps existing edits and avoids duplicates.
10. Image dimension bounding and invalid image rejection.
11. Interrupted processing recovery retains source photos and edits.
12. On-disk persistence across container reopening.
13. Generated imagery does not replace the original until explicitly selected.
14. UI add with required front photo, edit and verify saved name, delete.
15. UI create an outfit from existing wardrobe items.
16. UI search no-results and navigation to privacy information.

The first test run revealed prematurely released in-memory test containers and native iOS 26 search labels that differed from the initial selectors. Those test defects were fixed. A manual Keychain check found that disabling simulator code signing removes the required entitlement; simulator instructions and CI now use normal signing, with a regression test.

## Limits of this verification

- Camera capture, denied camera permission, Face ID/passcode, real label OCR, and Vision segmentation quality have not been exercised on a physical iPhone.
- Vision foreground cleanup was unavailable in the simulator; Drape preserved the original and displayed a recoverable explanation. Remote studio generation worked.
- The source garment is synthetic. Image generation visibly changes some details; screenshots and the app label it as an AI preview. This is not proof of exact garment fidelity.
- iOS 18 is the deployment target, but the tested runtimes were iOS 26.2 and 26.5. No iOS 18 runtime or device test was performed.
- No App Store Connect entry, signed distribution export, TestFlight upload, or App Review approval has been completed.
- Cloud storage/sync is an architectural follow-up, not an implemented feature.
- Before release, publish a completed privacy policy/support URL, finish App Store metadata/privacy answers, and perform the physical-device checks in `RELEASE.md`.

## iOS 17.6 compatibility — 10 October 2026

- Lowered the deployment target to iOS 17.6, including devices on iOS 17.6.1, in `project.yml` and the regenerated Xcode project.
- Replaced the iOS 18-only `Tab` API with `tabItem` while retaining Wardrobe, Looks, and Settings navigation. No model or stored-data changes.
- Signed Drape scheme tests on iPhone 17 Pro / iOS 26.5: **16 passed, 0 failed, 0 skipped**, including Keychain, persistence/photo restoration, and the three UI flows. Local results: `build/iOS17CompatibilityTests.xcresult`.
- Unsigned Release device archive succeeded at `build/Drape-iOS17.xcarchive`. Both its `MinimumOSVersion` and executable `LC_BUILD_VERSION` minimum are **17.6**; the simulator app also declares 17.6.
- No iOS 17 simulator runtime is installed. Compilation checks API availability for iOS 17.6, but execution on iOS 17.6.1 remains unverified. Before treating that version as device-tested, launch on the physical iPhone and check capture/import, save/relaunch, all three tabs, Vision processing, and device authentication.

## Managed AI development service — 10 October 2026

- Integrated latest `origin/main` (`a065804`, Luna/Seedream defaults) with the existing local iOS 17.6 work. The merge introduced no source-tree changes relative to the already-tested base.
- Signed simulator scheme: **20 passed, 0 failed** (16 unit tests, 4 UI tests), including the new Ask AI flow without a provider-key field or upload modal. UI tests disable outbound paid AI. Result bundle: `build/Logs/Test/Test-Drape-2026.10.10_09-17-51-+0200.xcresult`.
- Python/FastAPI gateway: **8 tests passed**, covering bearer authentication, provider-key isolation, model/settings validation, external-image-URL rejection, request-size and rate limits, safe provider failures without retries, and bounded studio requests.
- CapRover `drape-ai`: one healthy container, no mounts or published host ports, HTTPS enabled and enforced. `/healthz` returned revision `52fd87c5233139f2`. Missing authentication returned 401; authenticated invalid input returned 400. All 127 pre-existing app definitions matched the baseline.
- One paid live analysis through `https://drape-ai.cr.lvtd.dev/api/v1/chat/completions` succeeded with the synthetic cardigan JPEG. Reported cost: $0.0004643. It identified a cream cable-knit cardigan and left brand/size/care empty, but returned “Knitted fabric” as material despite the smoke prompt requesting fiber composition only. This validates transport, not metadata accuracy. The app's existing stricter analysis prompt remains in place and suggestions still require review. Evidence is in ignored `build/managed-ai-smoke/result.json`. Hosted studio generation was not paid-tested in this change.
- Unsigned Release archive succeeded at `build/Drape-release-check.xcarchive`. Its service URL and development credential are empty. Neither the Release app nor the Debug simulator app contains the OpenRouter key.
- Signed Debug device build succeeded and was installed and launched on the user-approved connected iPhone 14 Pro. No personal garment was uploaded during verification. The device's interactive Ask AI flow still requires user testing; installation/launch alone does not establish it.
- AI is enabled only in privately configured Debug builds. Production authentication/app attestation and durable quotas remain required before public distribution; the development throttle resets on service restart.
