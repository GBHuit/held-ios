# Keyvow｜键诺

**Every promise, kept.**

**每笔团购，承诺如初。**

Keyvow is a local-first iPhone and iPad app for mechanical-keyboard group buys and other long preorders. It keeps original promises, partial deliveries, evidence, per-currency funds, reminders, and portable backups together without requiring an account.

## First-release scope

- Multiple items, partial delivery, cancellation, refund requests, confirmed refunds, and disputes.
- Exact dates, ranges, month, quarter, season, and unknown delivery estimates.
- Original listing, terms, receipt, communication, shipping, and file evidence.
- On-device OCR from selected photos or the VisionKit document scanner, always with user review.
- HTTPS URL and plain-text intake through the Share Extension and App Group inbox.
- Optional local order reminders, lead times, and weekly summaries.
- Separate currency ledgers; no invented exchange rates or cross-currency totals.
- CSV, JSON, ZIP, and PDF export, plus previewed merge/replace restore.
- English and 简体中文 switching in the app; the Share Extension reads the saved language on its next launch.
- Free use for up to three active orders; optional non-consumable **Keyvow Pro** (`held.pro`) for unlimited active orders. Backup, export, restore, and existing-order access are not paywalled.

Release builds start empty. Fictional sample orders are installed only once in DEBUG and never automatically return after deletion.

## Project map

- `Held/` — SwiftUI, SwiftData, services, assets, privacy manifest, and localization catalog.
- `KeyvowShareExtension/` — native Share Extension, its localization, entitlements, and privacy manifest.
- `HeldTests/` — unit tests for storage, estimates, and localization.
- `KeyvowUITests/` — native navigation, language-switching, and screenshot tests.
- `Held.xcodeproj/xcshareddata/xcschemes/KeyvowScreenshots.xcscheme` — DEBUG screenshot-test scheme.
- `.github/workflows/ios-build.yml` — simulator build, XCTest, and optional native screenshot verification.
- `.github/workflows/ios-screenshots.yml` — reusable/manual iPhone and 13-inch iPad UI capture workflow.
- `.github/workflows/ios-release.yml` — manual Apple Distribution archive, dual-signature inspection, IPA export, and optional TestFlight upload.

`Held`, `com.held.groupbuy`, `com.held.groupbuy.ShareExtension`, and `held.pro` are stable implementation identifiers. The user-facing brand is Keyvow／键诺; do not migrate persisted data or StoreKit identifiers merely to remove the old internal name.

## Build and test

Requirements and physical-device installation are covered in `INSTALL.md`.

The application icon is restored from its checked-in Base64 parts and verified in CI:

```bash
ICON_BASE="Held/Assets.xcassets/AppIcon.appiconset/Held-1024"
cat "${ICON_BASE}.base64.parts"/part-* > "${ICON_BASE}.base64"
base64 --decode < "${ICON_BASE}.base64" > "${ICON_BASE}.png"
shasum -a 256 "${ICON_BASE}.png"
```

Expected icon SHA-256:

```text
225f4f83470d92bb64de57fe6e8411794a9d0674524407cbb1ce67b3e1f66d56
```

Run unit tests on an available iPhone simulator:

```bash
xcodebuild \
  -project Held.xcodeproj \
  -scheme Held \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Run native UI and screenshot tests:

```bash
xcodebuild \
  -project Held.xcodeproj \
  -scheme KeyvowScreenshots \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -resultBundlePath Keyvow-UI.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  test

xcrun xcresulttool export attachments \
  --path Keyvow-UI.xcresult \
  --output-path Keyvow-Screenshots
```

## Verified build boundary

GitHub Actions **Build #20** (`44271291449`) compiled commit `75d0bd74de96b051d0a238bde84c9fdfb42c8ce3` using stable Xcode 26 and passed **13 XCTest cases with 0 failures**. The downloaded test log ends with `** TEST SUCCEEDED **`.

That result does not prove physical-device behavior, App Group/StoreKit integration on device, Apple Distribution signing, TestFlight processing, App Store screenshot acceptance, or review approval. Check the current workflow run and its actual artifacts before treating a later commit as validated.

## Privacy and release

No ads, analytics SDK, tracking, account, or developer order-content server is used. Both targets include privacy manifests. Camera and notification access are optional and purpose-driven.

Public pages:

- English support: https://gbhuit.github.io/keyvow-support/support.html
- English privacy: https://gbhuit.github.io/keyvow-support/privacy.html
- 简体中文支持：https://gbhuit.github.io/keyvow-support/support-zh.html
- 简体中文隐私：https://gbhuit.github.io/keyvow-support/privacy-zh.html

The sibling `AppStore/` delivery folder contains bilingual metadata, review notes, IAP copy, signing setup, privacy/support source, and the capture/submission checklist. A simulator pass is not an App Store submission; complete the observed signing, TestFlight, device, screenshot, and account steps recorded there.
