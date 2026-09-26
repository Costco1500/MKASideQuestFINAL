# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

SideQuest is a native iPhone app plus an iMessage extension for planning group hangouts. It is built with SwiftUI, Messages and EventKit, and a small Python API. It has no web frontend and no third-party Swift packages. Python uses only the standard library.

## Commands

```sh
bash scripts/xcode.sh test                                          # all iOS unit + UI tests (iPhone 17 Pro simulator)
bash scripts/xcode.sh test -only-testing:SideQuestTests/PlanningTests   # one test class
bash scripts/xcode.sh test -only-testing:SideQuestUITests               # UI tests only
bash scripts/xcode.sh build
python3 backend/server.py                                           # API on 127.0.0.1:8787 (HOST, PORT, SIDEQUEST_DB)
python3 -m unittest discover -s backend -v                          # backend tests
python3 -m unittest discover -s backend -p 'test_sessions.py' -v    # one backend module (tests import siblings, so use discover)
ruby scripts/generate_project.rb                                    # after adding/removing Swift files (needs `xcodeproj` gem)
```

- `scripts/xcode.sh` sets `DEVELOPER_DIR` to full Xcode and uses **ad-hoc signing** (`CODE_SIGN_IDENTITY=-`). The Keychain tests fail on an unsigned simulator build, so run tests through this script rather than plain `xcodebuild`.
- The Xcode project is committed but generated. Target membership is folder-based in `scripts/generate_project.rb`, so a new `.swift` file isn't built until you re-run the generator.
- Development followed TDD with RED/GREEN checkpoint commits (`test: … RED` then `feat: … GREEN`). The evidence is in `docs/tdd-evidence.md` and `docs/ocr-session-tdd.md`. Update them when you add a guarded behavior.
- The Photos-picker UI test skips unless the three demo screenshots are in Simulator Photos. `docs/ocr-session-tdd.md` has the `xcresulttool export` + `simctl addmedia` steps to load them.

## Architecture

Xcode targets (defined in `scripts/generate_project.rb`):
- `SideQuestCore` (`iOS/Core`): a static library for pure logic and models. It is extension-API-only, so no UIKit/Messages app-only APIs.
- `SideQuest` (`iOS/App` + `iOS/Shared`): the containing app. It handles onboarding, profile and settings.
- `SideQuestMessages` (`iOS/MessagesExtension` + `iOS/Shared`): the `MSMessagesAppViewController` that hosts the SwiftUI quest flow. `iOS/Shared` is compiled into **both** app targets, not into Core.
- `SideQuestTests` / `SideQuestUITests`. The UI tests drive the real Messages app with the simulator's seeded conversation. They insert cards but never send them.

Core concepts (`iOS/Core`):
- `Participant`: each person's own profile, availability, budget, age range and approximate area. Budget is the group's lowest maximum.
- Chat import pipeline: chat screenshots go through `ChatScreenshotOCRService` (on-device Vision, one image at a time, in picker order) to produce `OCRTextBlock`s. `ScreenshotMessageParser` groups the blocks into sender/text `ImportedMessage`s, and `MessageImport` deduplicates them and handles Last 10/25/50 selection. There is no iMessage history API.
  - Try Demo renders `DemoChatScreenshots` from the editable demo chat script (Settings, stored in `QuestPreferences`, `Name: message` per line) and runs them through the same real OCR path.
  - Only selected sender/text pairs (at most 50) leave the device. OCR boxes and images never do.
- `AvailabilityEngine` + `CalendarProvider`: deterministic overlap. EventKit events become busy intervals right away, and titles, notes and attendees are dropped.
- `Planning`: `PlanningRequest`/`PlanOption`, `PlanRules` validation, `DemoPlanner` offline fallback, and `APIClient`. `APIClient` allows only HTTPS, or HTTP to localhost/127.0.0.1.
- `Session`: shared session, votes (`down`/`maybe`/`pass`), `VoteEngine` for the deterministic winner, and `SessionLink` carried in MSMessage URLs.

App state (`iOS/Shared/QuestStore.swift`):
- `QuestPreferences` stores the profile and server in the App Group `group.com.sidequest.shared`. If you rename it, update it together with `SideQuest.entitlements`.
- `MembershipVault` stores member tokens in each target's Keychain, not in the App Group.
- `QuestStore` polls the session every 5 seconds.
  - Async work runs through `workTask`/`readTask`, guarded by `lifecycleID`/`readID` tokens.
  - `reset()` and opening a different invitation call `cancelWork()`/`stopReading()`, so stale responses can't restore a reset session or overwrite another one.
  - New async paths should follow this token pattern; `SessionWorkflowTests` covers it.

Backend (`backend/`, standard library only):
- `server.py`: `ThreadingHTTPServer`. It rate-limits to 180 requests/min, caps bodies at 150 KB, sends `Cache-Control: no-store`, and its `log_message` is intentionally silent.
- `sessions.py`: `Service.dispatch` is the router.
  - Routes: `GET /health`, `POST /sidequest/plan`, `POST /api/sessions` (body `{expectedParticipantCount}`), `GET /api/sessions/{id}`, and `POST /api/sessions/{id}/{join|context|vote|finalize|plan}`.
  - Storage is SQLite. Tokens are stored as SHA-256 hashes, sessions expire after 7 days, and there are at most 12 participants.
  - The flow is invitation first, then profiles. The organizer creates the session and sends the invite card before entering a profile. Posting `context` marks that member Done.
  - The server rejects `plan` with 409 until the member count equals `expectedParticipantCount` and every member is Done. The app enforces the same gate, but the server check is the authoritative one.
  - The invite token allows joining and viewing. A member token allows only that member's own changes. Only the owner can finalize.
  - Joining or changing context calls `reset()`, which clears plans and votes.
- `planner.py`: validates the request, then makes one OpenAI structured-output call (`OPENAI_API_KEY`, `OPENAI_MODEL` default `gpt-4.1-mini`) and retries invalid output once. `validate_plans` enforces the windows, budget, age and area. It falls back to labeled `demo_plans`. Tests inject `model_call`, so they make no live calls.

The Swift `Codable` models in `iOS/Core` and the Python dicts in `backend/` define the same JSON by hand, with no shared schema. When a field changes, update both sides and both test suites.

## Invariants

- The OpenAI key is backend-only and never goes in the iOS targets.
- Never log or persist raw chat text. Screenshots and imports stay in memory and are cleared after planning or when the extension deactivates.
- Calendar details never leave the device; only busy intervals do. Availability and winner selection stay deterministic, and the AI is never the source of truth.
- The user always taps Send and confirms calendar saves in Apple's editor. The app never auto-sends or auto-saves.
- Plans have no confirmed venues, bookings or real prices.
