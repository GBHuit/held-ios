# Agent working rules — held-ios (Keyvow)

Two agents work on this repository. To stop overwriting each other's changes,
ownership is split as follows. These rules apply to every agent and every
human contributor.

## Build pipeline owner (Hermes / CEO agent)

Owns and is the only one who edits:

- `.github/**` — all workflows
- `*.xcodeproj/**` — project.pbxproj, schemes (`xcshareddata/xcschemes/**`)
- `*.storekit` — StoreKit test configurations
- `*.entitlements`, `Info.plist` signing keys, bundle identifiers
- Certificates, provisioning profiles, GitHub secrets
- Dispatching CI runs and interpreting their results

## Product code owner (Kimi)

Owns:

- `Held/**` — app source (SwiftUI, models, services)
- `KeyvowShareExtension/**`
- `KeyvowUITests/**` — test code (but NOT the scheme file that runs it)
- `KeyvowTests/**`
- Documentation: `README.md`, `INSTALL.md`, `AppStore/**`

## Rules

1. Do not edit `.github/**`, `*.xcodeproj/**`, `*.storekit`, or signing files.
   If a change there is required, describe it in the handoff and let the build
   owner apply it.
2. Before starting work, pull the branch — it may have moved while you were
   writing.
3. Before pushing, check whether a CI run is in progress
   (`gh run list` or the Actions tab). Do not push on top of a running build
   unless the build is known to be stale.
4. Build verification requests go through the user; do not dispatch runs to
   "see if it works" without an agreed change set.
5. Keep commits scoped: code changes in code commits, pipeline changes in
   pipeline commits. Never mix both in one push.
