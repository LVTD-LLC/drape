# Drape privacy policy

Draft for the first release. Publish this at a public HTTPS URL and add the operator's support contact before App Store submission.

Drape helps you keep a personal clothing catalogue and save outfits. The first version does not create a Drape account.

## Local data

Clothing photos, descriptions, favorites, and looks are stored in the app's private storage on your iPhone. Photos are resized and re-encoded to remove camera location metadata. Background removal and label text recognition run on the device. Depending on your device settings, app data may be included in an iCloud or computer device backup. Cross-device syncing is not offered in this version.

The optional app lock uses Apple's device authentication. Drape does not receive your facial data or device passcode.

## Optional AI

When you explicitly confirm an AI request, Drape sends the selected clothing photos to OpenRouter and the model provider you choose. Photos are used to suggest clothing details and, if you enable it, create a studio-style image. The providers' terms, retention, and privacy policies apply. See [OpenRouter's privacy policy](https://openrouter.ai/privacy) and the selected model provider's policy. Requests already sent to providers cannot be recalled by deleting local app data.

Your OpenRouter API key is stored in the iPhone Keychain with access restricted to this device while unlocked. It is sent only to OpenRouter to authenticate requests. It is not included in wardrobe exports or the app source code. Drape does not send your name, Apple account identifier, or location with AI requests.

The app remains usable without AI. You can disconnect OpenRouter in Settings. AI results may be inaccurate; compare generated images with originals and verify suggested size, fabric, and care against your clothing labels.

## Export and deletion

Exports include clothing photos, metadata, and saved looks. Export files are not encrypted by Drape; store them privately. Files saved to a cloud drive are subject to that provider's policies. You can restore a backup or delete all wardrobe data in Settings. Deletion also removes the saved OpenRouter key. Exported files and backups held elsewhere are not deleted automatically.

## Analytics and advertising

Drape includes no advertising, tracking, or analytics SDKs. OpenRouter and model providers may record request information according to their policies.

## Contact

The publishing operator must supply a working support email or support website before release. Do not publish this draft with an incomplete contact section.
