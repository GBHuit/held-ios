# Install Keyvow on an iPhone

`Held` remains the internal Xcode scheme, target, and source folder name. The installed app is named **Keyvow** in English and **键诺** in Simplified Chinese; keep the existing bundle IDs and the Pro product ID unchanged when signing.

## Requirements

- A Mac with Xcode 16 or newer for local development; the cloud release workflow uses the current stable Xcode 26 runner.
- An iPhone running iOS 17 or newer.
- An Apple Account added in Xcode Settings → Accounts.

## Personal-device installation

1. Open `Held.xcodeproj` in Xcode.
2. Select the **Held** project, then the **Held** target → **Signing & Capabilities**.
3. Enable **Automatically manage signing** and select your **Team**. The App Group must remain `group.com.held.groupbuy` for both the app and Share Extension.
4. Connect and unlock the iPhone. Trust the Mac on the phone, then select the phone as Xcode's run destination.
5. Build and run (`⌘R`). Xcode compiles, signs, installs, and launches Keyvow on the phone.
6. For a free personal team, open iPhone Settings → General → VPN & Device Management, trust your developer certificate if iOS asks, and reopen Keyvow. Free personal provisioning normally expires after seven days; reconnect to Xcode to reinstall or refresh it.

Do not use an iOS Simulator build on an iPhone. A simulator `.app` is not an installable device IPA. If you change either bundle identifier for local development, change the App Group consistently in both targets as well; otherwise shared-link import will not work.

## Optional macOS cloud build

The included `.github/workflows/ios-build.yml` can run on a GitHub-hosted Mac. Push the contents of this folder to a private repository, then run **Actions → Held iOS build → Run workflow** with the signed-IPA option off to perform a real simulator compilation and XCTest run.

For App Store distribution, use **Keyvow App Store release** and follow `../AppStore/release-setup.md`. That workflow uses separate App Store profiles for the app and Share Extension, checks both embedded signatures, exports `Keyvow.ipa`, and can optionally upload it to TestFlight. It requires the distribution certificate, both provisioning profiles, and—only for upload—the App Store Connect API key described there.

The legacy development-IPA path in `ios-build.yml` signs only the main app profile and is not the App Store release path. Do not mistake its development artifact for a TestFlight or App Store package.

## TestFlight / wider distribution

Use a paid Apple Developer Program membership. Create the App Store Connect app record for `com.held.groupbuy`, configure the two distribution profiles, and run the release workflow. TestFlight installation and physical-device checks are still required before review. App Store Connect also requires privacy declarations, screenshots, age rating, review contact information, and the first in-app purchase submission.

## Optional Keyvow Pro configuration

Core order tracking, evidence, reminders, and exports do not depend on Pro. To sell **Keyvow Pro**, configure a **non-consumable** App Store Connect product with the exact product ID `held.pro`. Load, purchase, restore, and verified-entitlement paths are present in the app. The app never treats a restored file as proof of purchase.

## Migration from the Web app

In the Web app, export JSON. On iOS, open **Settings → Backup & restore → Import**, choose the JSON, review the preview, then explicitly choose **Merge** or **Replace**. Web evidence entries preserve their metadata; files that existed only as browser placeholders cannot become real attachments. Native ZIP backups include actual imported attachments and SHA-256 verification.

## Verification boundary for this source handoff

The source project was produced on Windows. GitHub Actions Build #20 (`44271291449`, commit `75d0bd74de96b051d0a238bde84c9fdfb42c8ce3`) compiled it with stable Xcode 26 and passed **13 XCTest cases with 0 failures**, including four localization tests. The real `test.log` records `** TEST SUCCEEDED **`; this is a simulator result, not a physical-device or App Store signature approval.

Native iPhone/iPad UI screenshot testing has a separate manual workflow. Physical installation, App Group sharing, camera/OCR, notifications, file import/export, StoreKit sandbox, backup/restore, and final layout review still require their observed device or App Store Connect results. Do not treat the simulator test pass as production approval or as a signed App Store IPA.
