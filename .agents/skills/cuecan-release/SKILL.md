---
name: cuecan-release
description: Build a CueCan for Mac release, or change how updates, the news line or the beta's time limit work. Covers the release workflow, `scripts/release.sh`, what they need and produce, signing and notarization, the update feed, build numbers, the addresses and keys that can never change, and the 90-day limit stamped into each build. Use when cutting a release, touching Sparkle, `UpdateKit`, the news check or `BetaExpiry`, or changing anything the app asks the network for.
---

# Releases, updates and the beta limit

## Who can release

A release needs things only the maintainer has: the Developer ID certificate, a notary login, and the private half of the update signing key. A fork needs its own bundle id, name, feed address and keys before it can ship anything.

## How a release is made

Pushing a tag `v<version>` runs `.github/workflows/release.yml`. The tag has to match the app's `MARKETING_VERSION`, or the run stops. So does a version with no section in `CHANGELOG.md`: that section becomes the release's notes.

1. It imports the certificate and passes the notary key and the update key from the `release` environment's secrets.
2. It runs `scripts/release.sh`, below.
3. It attests the DMG, so `gh attestation verify` can tie a download to the run that built it.
4. It creates a **draft** GitHub release with the DMG, its SHA-256 and `appcast.xml`.

Nothing reaches anyone until the maintainer publishes the draft. The app's feed address is on the project's website, which sends it to the latest published release's `appcast.xml`.

- **Never push a tag or publish a release yourself.** Both are the maintainer's.
- **A change to the workflow is a change to who can sign.** Keep the secrets in the `release` environment, never add a `pull_request` trigger to it, and raise any change to its permissions or triggers first.
- `.github/workflows/test.yml` builds and tests on pull requests, with no secrets.

## What the script does

```sh
scripts/release.sh                  # build, sign, check, make the DMG, notarize
scripts/release.sh --skip-notarize  # stop before sending anything to Apple
```

1. Archives a Release build with the Developer ID identity and a secure timestamp.
2. Signs Sparkle's helpers and checks the signatures.
3. Makes the DMG.
4. Notarizes it with Apple, staples it, and checks it as Gatekeeper will.
5. Writes `appcast.xml`, the update feed, signed with the update key.

Everything lands in `build/release`, with the DMG's SHA-256. **The script uploads nothing:** the workflow attaches the files to a draft release.

- **Notarizing sends the build to Apple.** Ask the maintainer before running without `--skip-notarize`.
- **Overrides:** `IDENTITY`, `TEAM`, `NOTARY_PROFILE`, `SPARKLE_ACCOUNT`, `DOWNLOAD_URL_PREFIX`, `OUT`, `BUILD`, `BUILT_ON`.
- **Keys from the environment, as the workflow gives them:** `NOTARY_KEY`, `NOTARY_KEY_ID` and `NOTARY_ISSUER` in place of the saved login, and `SPARKLE_PRIVATE_KEY` in place of the keychain.

## Build numbers

The build number is the number of commits, and Sparkle offers an update only when it's higher than the installed one. The workflow checks out the whole history for that reason. If the history is rewritten, or releases move to another repository, the count restarts: pass `BUILD` with a number above the last release.

## What can never change

Every installed copy has these built in. Change one and existing copies stop updating, or stop hearing from the project.

- The update feed's address (`SUFeedURL`) and the update key (`SUPublicEDKey`), in `Config/CueCan-Info.plist`.
- The news endpoint's address, in `NewsModel`.
- The bundle id.

The private half of the update key has no way back if it's lost. It never expires, and a new key can only be shipped in an update signed with the old one.

## The beta's time limit

- The script stamps the day it runs into the app (`CUECAN_BUILT_ON`, which becomes `CueCanBuiltOn` in the Info.plist).
- `ProjectKit.BetaExpiry` reads it. For 90 days the build records; after that, starting a recording shows an alert with an update button. What's already recorded still opens, edits and exports.
- A build made in Xcode has no day and never expires.
- **So a release has to follow within 90 days of the last,** or every copy stops recording until one does.

Check a built app's stamp:

```sh
plutil -p CueCan.app/Contents/Info.plist | grep CueCanBuiltOn
```

## What the app asks the network for

Three kinds of request, and the project's privacy page lists them. Adding a fourth, or sending anything more, is a change to a public promise: raise it first, and change the page with the code.

| Request | Code | What's sent |
| --- | --- | --- |
| The update feed, about daily | `UpdateKit.AppUpdater` (Sparkle) | Nothing about the Mac; no system profile |
| A line of news, at most daily | `NewsModel`, with `ProjectKit.NewsItem` and `NewsState` | A random identifier made on the Mac, to count copies in use |
| The speech models, once | `TranscribeKit.SpeechModels`, `TimingModelDownload` | Nothing |

- One switch in Settings turns the first two off together.
- The news endpoint answers `{}` or `{"id", "text", "link"}`. The app draws one line and nothing else: at most 140 characters, an `https` link, no markup. Anything else is treated as no message.
- A dismissed message never shows again, so a new message needs a new `id`.
