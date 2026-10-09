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
