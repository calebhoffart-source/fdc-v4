# Fourth Down Coach V4 — FINAL FREE SOURCE PROJECT

**Build status (October 24, 2026):** Complete native iOS source bundle. Local `swiftc -frontend -parse` and package checks passed; nine pure-rule tests passed. **Not compiled by Xcode, signed, installed, or verified on an iPhone in this environment.** A GitHub Actions workflow is provided to compile and export an **unsigned** IPA. The GitHub build must pass before treating this as an installable candidate.

## What this is

Native **SwiftUI** (not a cramped WebView) iPhone 16-oriented app with local persistence, Apple Vision camera pose detection, on-device OCR, optional local speech and scheduled notifications. It contains no Apple paid/restricted `FamilyControls`, `ManagedSettings`, or `DeviceActivity` entitlements, and requires no cloud account or external AI subscription.

### Included functionality

| Category | What is implemented in source | Honest limitations |
|---|---|---|
| First launch | Setup page; three separate O-line, D-line and controlled-tackle calibration steps with 3 recognized movement cycles each; can defer calibration | Learns 2D knee-angle movement ranges, **not a trained football model**. Cannot validate tackle safety, contact, hand placement, pad level; test in clear space with adult/coach oversight. |
| Live camera | Back camera Vision joints + stance→extension→reset cycles; reject invisible/missing joints; 1.6s cooldown; re-calibrate; no-dummy footwork option | Recognition may miss or double-count reps; **not hardware-tested**. It doesn't verify dummy contact. |
| Film room | Record local QuickTime clip during a camera session; playback inside app | No automatic video analysis or referee that overturns calls; users review film manually. Device recording still needs testing. |
| Bank and loans | One detected rep earns 1 voluntary bank minute (2 during displayed bonus window); user can mark earned time spent; travel loans add 1 future-credit repayment minute per 10 borrowed minutes | This is **an honor ledger, not iOS Screen Time**. It cannot unlock/lock TikTok, games, or other apps. |
| Daily accountability | Screenshot uploader (PhotosPicker); on-device Vision text recognition; manually confirm date and recreational hours/minutes; yesterday's report becomes today's 1:1 accountability rep *target* | No automatic screen usage access. OCR suggests a number but user must confirm it and the correct day. A high target never requires unsafe rep volume. |
| Healthy training limit | Cap of 50 app-credited physical reps/day, at most 8 controlled tackle movements, at most 15 manual/unverified logs; rest/recovery/season pause | Screen-time accountability target may be larger than workout cap; excess is a reflection/behavior goal, **not exercise debt**. |
| Accountability | Daily commitment, start/end checkpoints, Coach trust/consistency rating, prior missed-commitment check, weekly summary, 2-minute comeback challenge | Trust is a personal commitment score; it does not prove honesty. |
| Coach requests | Working in-app request form for spending earned minutes or travel borrowing; reschedule reason review; leave/recovery/no-dummy/season commands; local rules fallback | Some iOS 26+ devices may optionally use Apple Foundation Models for **dialogue only**. No paid remote generative AI; fallback Coach is rules-based. |
| Voice | Voice-to-text **only when on-device speech recognition is available**; read Coach responses with iOS text-to-speech | Speech may be unavailable; text mode always works. |
| Notifications | Local notifications for Screen Time audit, a few daily check-ins, workout schedule, max 5 escalating late reminders, weekly grade checks, recurring deterministic 2X windows; off-season/recovery quiet hours | iOS decides exact delivery and permissions; 5-day workout notifications are refreshed when the app opens; not an endless spam system. No background live Screen Time reading. |
| School | Gradebook screenshot local OCR, user-reviewed subject/grade/period, 70% warning, 20-minute study assignment for low grades, study log | No school account access or automatic screenshot authentication. No punishment workout. |
| Extras | Phone-free voluntary 15/30/60-minute focus/lock-in timer, local interruption flag, character progression, season pause, no-dummy mode | Focus cannot block app switching or accurately prove no other app use. Level is based on logged training. |

### V4's core timeline

1. **Monday** you use your phone. No automatic monitoring in the free build.
2. **Tuesday morning**, Coach requests a **screenshot of Monday's** iOS Screen Time daily view.
3. You confirm the **recreational** usage (e.g., 2h 15m = 135 min).
4. **Tuesday's dashboard** shows a 135-rep accountability *target*, but Coach assigns at most a safe 50 physical repetitions. It never creates hundreds of forced tackles or accumulated punishment reps.
5. Coach nudges/checks in at scheduled times and gives the next weekly accountability report.

## How to build the unsigned IPA using your Windows PC and GitHub

1. Unzip this package.
2. In an empty GitHub repository (or a *new branch* of your old repository), place the **contents** of this folder at the repo root. `project.yml`, `ios/`, `tests/`, and `.github/workflows/ipa.yml` must be at the root — **do not upload them inside another `fdcbuild` or ZIP-wrapper folder**.
3. In GitHub, open **Actions → Build free Fourth Down Coach V4 IPA → Run workflow** on your branch. The workflow also triggers when `main` is pushed.
4. Wait for the actual **green build**. If it fails, download `FourthDownCoach-V4-BUILD-LOG` and use the Xcode compilation error; the unsigned file will not exist after a failed build.
5. If green, open the run → **Artifacts** → `FourthDownCoach-V4-unsigned-IPA` → download and unzip → `FourthDownCoach-V4-UNSIGNED.ipa`.
6. Install/sign only with a tool and Apple Account you trust (e.g., working Sideloadly/iPASide). Device detection or a ZIP download is **not proof installation succeeds**. Free Apple provisioning often expires after 7 days; sign-in or certificate errors can still occur.
7. On iPhone: authorize camera, Photos and optional speech/notifications. Test calibration with a trainer before trusting any rep data. Enable **Offseason Training** only outside school football season.

### Build on a Mac (if available)

```sh
brew install xcodegen
xcodegen generate --spec project.yml
open FourthDownCoach.xcodeproj
```

Configure your own signing team with the free Apple ID option where available; **no paid Family Controls entitlement is included**. Use the `FourthDownCoach` target and an iPhone running iOS 17.4 or newer.

## Why app blocking and actual screen usage remain unsupported

Apple protects access to usage metrics and app shields behind Screen Time API entitlements. This **free** V4 project intentionally does not request them. Local notifications, camera pose estimation, photo OCR, and a self-reported Screen Time ledger don't require that restricted entitlement. You may configure **iOS Settings → Screen Time → App Limits** separately (including a parent-managed passcode), but it cannot dynamically exchange earned minutes with this app.

You can also manually add iPhone **Shortcuts → Automation → App → Is Opened → Run Immediately → Show Notification** for individual distracting apps, with a prompt such as "Every minute counts toward tomorrow's Coach target." Apple requires that App-open automation to be set up by the user; this project does **not** silently install it.

## Permissions and privacy

- `Camera`: only while camera calibration/tracking is open. Video film files are stored in the app's Documents/Films folder.
- `Photos`: pick only the screenshots you want. The app doesn't save the raw Screen Time or gradebook screenshot after running OCR. Text extracted from these images appears in the interface only for review.
- `Microphone` and `Speech Recognition`: optional for Coach voice commands, configured to require on-device recognition or use text instead.
- `Notifications`: optional local reminders. Quiet hours default to 9 PM–7 AM. Recovery and season pause suppress scheduled Coach reminders.
- `Apple Foundation Models`: optional dialogue on eligible iOS 26+ devices. It is **not used** to grade reps, lock apps, or award credit; behavior is deterministic without it.
- No servers, ad trackers, logins, paywalls or external API keys are part of the project.

## Test checklist for your iPhone

See [`docs/DEVICE-TEST-CHECKLIST.md`](docs/DEVICE-TEST-CHECKLIST.md). **Unverified items must be tested before calling the finished IPA fully functional.**

Apple references:

- [Vision body pose](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images)
- [UserNotifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
- [Screen Time API entitlement](https://developer.apple.com/documentation/xcode/configuring-family-controls)
- [PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker)
