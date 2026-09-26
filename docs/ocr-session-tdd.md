# Screenshot import and everyone-Done session milestone

Source: the supplied screenshot → OCR → selection → LLM brief and the requested workflow: send an invitation first, import screenshots, collect everyone's profile and Done, generate plans, vote, then insert the winner into Messages. ECC `tdd-workflow` was used with tests before implementation. These checkpoints preserve the evidence if the feature is later squash-merged.

| Behavior | RED evidence | GREEN evidence |
|---|---|---|
| Native screenshot import, selected-message payload, and session readiness | `76d095c`: intended compile failures for missing OCR/readiness APIs | `0afbf88`: 51 native unit tests passed, including actual Vision OCR of generated demo screenshots |
| Invitation before profile entry; server waits for every expected person | `aff4959`: new creation contract returned HTTP 400; 14 session tests failed at that missing contract | `8945be0`: all 28 backend tests passed |
| Photo batches are processed one at a time; actual Photos selections reach the existing planner inside Messages | Behavior-preserving refactor after GREEN | `7bbc242`: 53 unit tests passed; picker UI imported three images, recognized eight messages, and generated plans |
| Obsolete responses cannot restore a reset session or replace another session | `9780c87`: 6 workflow tests executed with 4 failing assertions | `81cb533`: all 53 native unit tests passed, including both lifecycle regressions |

| Passing guarantee | Test target | Type |
|---|---|---|
| Picker order and top-to-bottom OCR order survive reconstruction; sender labels and nearby lines combine; Unknown text remains | `ScreenshotImportTests` | Native unit |
| Adjacent and overlapping normalized duplicates are removed; Last 10/25/50 works | `ScreenshotImportTests` | Native unit |
| Analysis contains at most 50 selected sender/text records, with no OCR boxes, images, metadata, or unselected text | `ScreenshotImportTests` | Native unit |
| Default and edited demo scripts render into images and traverse real Vision OCR and the parser | `ScreenshotImportTests` | Native integration |
| Invitations exist before profile entry; absent invitees and invalid profiles prevent readiness | `SessionWorkflowTests`, `backend/test_sessions.py` | Native unit / service integration |
| The final Done unlocks one successful model call; forged readiness and excess participants are rejected; raw chat is not stored | `backend/test_sessions.py` | Service integration |
| Two HTTP clients join, complete context, plan, vote, and finalize; context changes invalidate plans and stale model results | `backend/test_http.py`, `backend/test_sessions.py` | HTTP / storage integration |
| Reset cancels pending invitation insertion; a different session's response cannot overwrite the active session | `SessionWorkflowTests` | Native integration |

Commands used for the relevant suites:

```sh
bash scripts/xcode.sh test -only-testing:SideQuestTests
bash scripts/xcode.sh test -only-testing:SideQuestTests/SessionWorkflowTests
python3 -m unittest discover -s backend -p 'test_*.py' -v
python3 -m coverage run --source=backend -m unittest discover -s backend -p 'test_*.py'
python3 -m coverage report --omit='backend/test_*.py'
```

The Xcode wrapper selects the iPhone 17 Pro Simulator and uses local ad-hoc signing for Keychain tests. Xcode/xccov unit-run line coverage: SideQuestCore **93.8%**, MessageImport **100%**, ScreenshotMessageParser **98.5%**, ChatScreenshotOCRService **98.8%**, QuestStore **85.4%**. Python production statement coverage: **96%** overall, **97%** for sessions; test files excluded. Model calls are stubbed in the automated backend tests.

Final validation on implementation revision `7bbc242`: **53 unit + 9 UI tests passed, zero failures or skips**, using `bash scripts/xcode.sh test` after pushing the branch. The UI suite covers the actual three-photo import inside Messages, selection/sender correction, invitation insertion before profile entry, voting, calendar presentation, and winning-card insertion. The final unsigned Release iPhone build also passed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SideQuest.xcodeproj -scheme SideQuest -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/Device CODE_SIGNING_ALLOWED=NO build
```

Final Xcode result: `build/DerivedData/Logs/Test/Test-SideQuest-2026.09.26_12-57-07--0400.xcresult` (local, ignored build artifact). Final `xccov view --report --json` coverage: app **84.5%**, core **94.0%**, Messages extension **78.7%**; production target-weighted aggregate **84.1%** (2,894/3,440 instrumented lines; shared sources appear in multiple targets). OCR **98.8%**, parser **98.5%**, store **82.8%**. UI presentation branches account for remaining gaps. Physical-device installation, live LLM calls, and cross-device iMessage delivery were not exercised. Apple still requires the user to tap Send on inserted cards.

The Photos integration UI test needs the three demo screenshots in Simulator Photos. They are exported as attachments by `ScreenshotImportTests/testDemoFixturesRunActualVisionOCRThenParser()`. Set `TEST_RESULT` to that run's `.xcresult` path, export them, boot the test simulator, then import the PNGs:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun xcresulttool export attachments --test-id 'ScreenshotImportTests/testDemoFixturesRunActualVisionOCRThenParser()' --path "$TEST_RESULT" --output-path build/OCRFixtures
# With the iPhone 17 Pro Simulator booted:
xcrun simctl addmedia booted build/OCRFixtures/*.png
```

The picker test explicitly skips when fewer than three screenshot fixtures exist; the verified run used all three and did not skip. Photo thumbnails expose image accessibility elements, so the UI test taps their measured centers.

Next milestone: add a Share Extension that reuses the existing App Group to hand selected screenshots to the same on-device OCR and review flow. No Share Extension is included in this milestone.
