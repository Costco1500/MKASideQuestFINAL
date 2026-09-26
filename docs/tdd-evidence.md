# Native rebuild TDD evidence

Source: the supplied SideQuest native iOS brief. Workflow: ECC `tdd-workflow`, tests before each implementation, with unsquashed checkpoints on `codex/native-ios-sidequest`.

| Journey / guarantee | RED checkpoint and observed failure | GREEN evidence |
|---|---|---|
| Containing app and Messages extension open | `279fbdc`: onboarding UI assertions failed on the empty shell | `685d45a`: app UI + embedded extension + actual Messages launch passed |
| Each person supplies a valid profile; lowest budget wins | `423eceb`: missing Participant/DemoData compile failures | `34eb5c0`: 4 ProfileTests passed |
| Only selected imported messages are analyzed; deduplicate/cap 50 | `afa2da5`: missing MessageImport compile failures | `d8cf27f`: 4 MessageTests passed |
| Deterministic shared availability and calendar permissions | `2b4baeb`: missing AvailabilityEngine compile failures | `62f178d`: 6 AvailabilityTests passed; both targets built |
| Three validated plans, one call, bounded retry, offline fallback | `630d873`: missing planning models/module; `83f7ef2`: missing HTTP server | `e839092`: 6 PlanningTests + 9 backend tests passed |
| Shared joins, own-context updates, votes, deterministic winner | `c55d147`: missing session models and storage implementation | `8920a60`: 25 unit tests, Messages launch/vote/card UI flows, backend persistence/concurrency tests passed |
| Winning event opens a confirmation editor; invalid winner blocked | `6069270`: missing Add to Calendar UI; over-budget received winner was incorrectly accepted | Full simulator run passed 26 unit + 4 UI tests; calendar editor opened and canceled |
| Native HTTP/member persistence integration | `ae26fd1`: unsigned simulator failed Keychain storage; 3 assertions failed | Same 4 client/store tests passed with local ad-hoc simulator signing |
| Demo "Read this chat" reveals an editable script, pre-selected, and stops when Messages closes | `0818747`: missing `DemoData.chatScript` compile failures | 33 unit tests passed (2 new MessageTests, updated offline journey, new stop-reading store test); app demo UI test reads the chat before planning. See note below |

Actual commands: `bash scripts/xcode.sh test`, focused runs using `-only-testing:SideQuestTests/<class>` or `-only-testing:SideQuestUITests`, and `python3 -m unittest discover -s backend -v`. Runtime RED was used for the shell, winning event, received-winner constraints, and Keychain regression. Other initial REDs were compile/import failures directly caused by missing feature implementations. Early test harness setup failures and a zero-test discovery run were not counted as evidence.

UI tests cover onboarding, demo generation/voting/finalization, Apple's event editor (cancel), opening inside Messages, expanded presentation, and inserting a poll into the compact compose field without sending. Tests wait for extension transitions/scrolling to settle before taps.

HTTP tests exercise actual local sockets for planning and two separate members joining, voting, and finalizing. Storage tests verify concurrent vote replacement, restart persistence, permission boundaries, and invalidation after context changes. Model calls are stubbed; no live OpenAI request was made.

Coverage is measured by Xcode/xccov and Python coverage. Final measurements are recorded below after the final run. The Apple permission grant path, calendar save into a real account, physical iPhone installation, and delivery between two real iPhones remain manual checks. No signing identity or connected physical device was available. EventKit objects are discarded before data leaves the provider.

No checkpoint commits were squashed or rewritten. Logs and `.xcresult` bundles remain in the local build output; no raw user conversations or credentials are committed.

## Final verification — 2026-09-26

- `bash scripts/xcode.sh test`: **30 unit + 7 UI tests passed**, no skips. This includes winning-event Calendar UI and final-card insertion inside Messages itself.
- Xcode line coverage: **SideQuestCore 90.0%, SideQuest app 87.5%, Messages extension 80.2%**.
- `python3 -m coverage run --branch --source=backend -m unittest discover -s backend -v`: **20 tests passed**. Backend statement coverage **95.1%**, branch coverage **78.1%**, combined **88.7%** (test files excluded).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SideQuest.xcodeproj -scheme SideQuest -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/Device CODE_SIGNING_ALLOWED=NO build`: **BUILD SUCCEEDED**. This is an unsigned compilation, not device installation.
- `git diff --check`: passed.
- Final Xcode result: `build/DerivedData/Logs/Test/Test-SideQuest-2026.09.26_00-06-57--0400.xcresult`.

Remaining unexecuted paths are live OpenAI service behavior, real EventKit permission grants and saved events, physical-device signing/install, and actual message delivery between devices. Mocked OpenAI wire-format, native HTTP/Keychain integration, two-member HTTP sessions, and local SQLite restart behavior are tested. Direct Google OAuth remains deferred as requested.

## Demo "Read this chat" — 2026-09-26

- `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:SideQuestTests`: **33 unit tests passed**.
- `-only-testing:SideQuestUITests` on the same simulator: the 3 containing-app UI tests passed, including the updated demo journey (Load demo chat → 8 selected → plans → vote → calendar editor). The 4 Messages-extension UI tests failed at the first extension element. The unchanged baseline `3dc430c` fails `testMessagesExtensionOpens` identically on this machine (Xcode 27.0, iOS 27 "iPhone 17"; no "iPhone 17 Pro" simulator installed), so these are environment failures, not regressions. Re-run on the original iPhone 17 Pro setup before relying on them.
