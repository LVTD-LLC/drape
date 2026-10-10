# Drape privacy policy

Draft for the first release. Publish this at a public HTTPS URL and add the operator's support contact before App Store submission.

Drape helps you keep a personal clothing catalogue and save outfits. The first version does not create a Drape account.

## Local data

Clothing photos, descriptions, favorites, and looks are stored in the app's private storage on your iPhone. Photos are resized and re-encoded to remove camera location metadata. Background removal and label text recognition run on the device. Depending on your device settings, app data may be included in an iCloud or computer device backup. Cross-device syncing is not offered in this version.

The optional app lock uses Apple's device authentication. Drape does not receive your facial data or device passcode.

## Optional AI

When you tap Ask AI or Add and ask AI, Drape sends the selected clothing photos through its AI service to OpenRouter and its model providers. The adjacent disclosure explains each upload. The service forwards photos in memory without storing a wardrobe copy. Photos are used to suggest clothing details and, if you enable it, create a studio-style image. The providers' terms, retention, and privacy policies apply. See [OpenRouter's privacy policy](https://openrouter.ai/privacy) and the selected model provider's policy. Requests already sent to providers cannot be recalled by deleting local app data.

Drape manages the OpenRouter credentials on its server. Users do not supply an API key. Private development builds use a separate development access credential; this is not the public-release authentication design. Drape does not send your name, Apple account identifier, or photo location metadata with AI requests. The gateway receives network information needed to serve the request, including the connecting IP address.

The app remains usable without AI. AI results may be inaccurate; compare generated images with originals and verify suggested size, fabric, and care against your clothing labels.

## Export and deletion

Exports include clothing photos, metadata, and saved looks. Export files are not encrypted by Drape; store them privately. Files saved to a cloud drive are subject to that provider's policies. You can restore a backup or delete all wardrobe data in Settings. Deletion also removes any legacy customer key saved by earlier development builds. Exported files and backups held elsewhere are not deleted automatically.

## Analytics and advertising

Drape includes no advertising, tracking, or analytics SDKs. OpenRouter and model providers may record request information according to their policies.

## Contact

The publishing operator must supply a working support email or support website before release. Do not publish this draft with an incomplete contact section.
