# Install Held on an iPhone

## Requirements

- A Mac with Xcode 16 or newer.
- An iPhone running iOS 17 or newer.
- An Apple Account added in Xcode Settings → Accounts.

## Personal-device installation

1. Open `Held.xcodeproj` in Xcode.
2. Select the **Held** project, then the **Held** target → **Signing & Capabilities**.
3. Enable **Automatically manage signing** and select your **Team**. If `com.held.groupbuy` is already registered by someone else, choose your own unique Bundle Identifier.
4. Connect and unlock the iPhone. Trust the Mac on the phone, then select the phone as Xcode's run destination.
5. Build and run (`⌘R`). Xcode compiles, signs, installs, and launches Held on the phone.
6. For a free personal team, open iPhone Settings → General → VPN & Device Management, trust your developer certificate if iOS asks, and reopen Held. Free personal provisioning normally expires after seven days; reconnect to Xcode to reinstall or refresh it.

Do not use an iOS Simulator build on an iPhone. A simulator `.app` is not an installable device IPA.

## Optional macOS cloud build

The included `.github/workflows/ios-build.yml` can run on a GitHub-hosted Mac. Push the contents of this folder to a private repository, then run **Actions → Held iOS build → Run workflow** with the signed-IPA option off to perform a real simulator compilation.

To produce a development IPA, first add the iPhone UDID to a development provisioning profile. Turn the signed-IPA option on, enter your Team ID and profile name, and configure these repository secrets:

- `IOS_CERTIFICATE_BASE64`: base64 of your Apple Development `.p12` certificate.
- `IOS_CERTIFICATE_PASSWORD`: the `.p12` export password.
- `IOS_PROVISIONING_PROFILE_BASE64`: base64 of the matching `.mobileprovision` file.

The workflow imports the identity into a temporary runner keychain, archives and exports the development IPA, inspects the embedded signature, and deletes the temporary identity afterward. Download `held-signed-development-ipa` from the successful run and install it using Xcode's Devices window or Apple Configurator. The profile must include your phone, and the phone must trust that development certificate. This workflow has been added but not executed in this session.

## TestFlight / wider distribution

Use a paid Apple Developer Program membership. Select **Any iOS Device (arm64)**, archive with **Product → Archive**, then use **Distribute App**. App Store Connect requires the Bundle ID, signing profile, privacy declarations, screenshots, and review information. TestFlight distribution also requires the appropriate App Store Connect record and tester setup.

## Optional Held Pro configuration

Core order tracking, evidence, reminders, and exports do not depend on Pro. To sell Held Pro, configure a **non-consumable** App Store Connect product with the exact product ID `held.pro`. Load, purchase, restore, and verified-entitlement paths are present in the app. The app never treats a restored file as proof of purchase.

## Migration from the Web app

In the Web app, export JSON. On iOS, open **Settings → Backup & restore → Import**, choose the JSON, review the preview, then explicitly choose **Merge** or **Replace**. Web evidence entries preserve their metadata; files that existed only as browser placeholders cannot become real attachments. Native ZIP backups include actual imported attachments and SHA-256 verification.

## Verification boundary for this source handoff

The source project was produced on Windows. It has not yet been compiled, installed, visually reviewed on iOS, or exercised on a physical device. Complete those checks in Xcode before considering it production-ready. Camera, local notifications, file import/export, and StoreKit should each be tested with the relevant device and App Store sandbox configuration.
