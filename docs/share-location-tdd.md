# Share, location, venues, and warm native UI

Milestone: September 26, 2026. Branch: `codex/native-ios-sidequest`. Journeys derive from the supplied native milestone: screenshot sharing, private location, grounded planning, and the instant Messages demo.

## Test-first checkpoints

ECC's `tdd-workflow` was followed sequentially. Each RED checkpoint was run before its implementation and committed; its GREEN partner passes the same checks.

| Behavior | RED | GREEN |
|---|---|---|
| Private server credential loading | `1f646b8` missing loader | `8438dd4` protected file, environment precedence, missing-file fallback |
| App Group text handoff and embedded image Share target | `d9f73f7` missing store | `ea83ac2` round trip, clear, unavailable group, image activation |
| Location privacy and real venue model/resolver | `2e0202a` missing types/schema | `373ecce` centroid, coarse wire coordinates, optional venue, injected lookup |
| Ground plans before voting/calendar | `a970aba` missing service injection | `56cc636` real store pipeline with injected venue results |
| Warm palette and instant chat input | `96d9684` missing palette/fixture | `dd46d06` 38 messages, existing selection, light/dark contrast |
| Preserve a new import while a poll is open | `6bd59a4` missing injectable review | `0016c77` review consumes drafts; current polls leave imports pending |
| Skip parking results for park hangouts | `a6f5ab3` missing result selection | `b1f5edd` native fixture verifies a park result or nil |
| Bind live output to group constraints | `7d14f8b` schema lacked budget bounds | `e14ea02` minimum budget, age ceiling, and supplied area enum |
| Return from Maps after extension recreation | `b347c31` missing resume behavior | `5e30c78` restores once, expires after ten minutes, contains no access token |
| Keep MapKit results near the group | `7630830` accepted a distant result | `f6dd90f` rejects results beyond 25 km |
| Keep venue searches concise | `4a60994` unbounded compound queries | `f05940a` one category, maximum 80 characters |
| Reject malformed venue updates | `577ba58` unexpected type errors | `5364539` 400 errors without mutating plans |

Unit tests inject venue lookups and disable live planning in `QuestStore`. Live OpenAI and MapKit checks belong to the integration/demo path, not the unit suite.

## Verified integration behavior

- Live server calls returned `source: ai`, exactly three plans, nonempty `venueSearchQuery` values, and no model coordinates. The final four-person request returned costs of $14, $12, and $13 against a $15 group ceiling in 5.5 seconds, with search categories “pottery studio”, “art gallery”, and “art supply store”. The server privately loads `gpt-4.1-mini` credentials outside the checkout. No key value appears in source or this evidence.
- A real MapKit result, Blick Art Materials in Atlanta, opened in Apple Maps. Returning to Messages restored the winning session; expanding the system sheet allowed Calendar and the winning-plan draft to complete. The draft was removed without sending and Calendar was cancelled without saving.
- Photos → Share → SideQuest ran Vision sequentially on three real screenshot assets. The extension reported extracted messages and returned to Photos. Messages displayed the pending import; Review consumed it. The analysis path deduplicated the overlap to eight messages and generated plans.
- Photos can provide images in library order. Overlap may remain visible during review; the existing selected-message pipeline removes duplicate sender/text pairs before planning.
- CoreLocation's When In Use prompt was granted in Simulator. A one-time simulated Atlanta coordinate produced a friendly area. Manual area entry remained available. The explicit demo fallback was not used by this test.
- The Maps handoff test uses the existing labeled offline planner with stable categories, then performs real MapKit searches. Other demo tests and the separate HTTP check exercise live LLM planning. No fixture venue coordinates are injected into UI tests.
- Xcode lists the containing app, Messages extension, and new Share Extension. The existing App Group is used by all three; no project regeneration was performed.

## Build and test evidence

- `xcodebuild -list -project SideQuest.xcodeproj` lists the app and both extension schemes/targets.
- Release iPhone build (unsigned): `xcodebuild -project SideQuest.xcodeproj -scheme SideQuest -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/Device CODE_SIGNING_ALLOWED=NO build` passed, including both embedded extensions.
- 68 native unit tests passed. The added venue-selection and Maps-return tests use in-memory fixtures, with no live MapKit calls.
- All 12 UI scenarios passed across the full suite and focused reruns. The full run at `2026.09.26_14-42-54` passed ten scenarios; the Photos picker initially raced its asynchronous thumbnail load, and the Maps test depended on variable LLM queries. After fixing the harness, the Photos picker passed at `14-54-05` and the complete Maps/Calendar/share sequence passed at `15-00-39` (local bundles are in `build/DerivedData/Logs/Test`). The final Maps check uses native scrolling after sheet expansion; the earlier custom drag accidentally reopened Maps.
- 37 backend tests passed; production statement coverage is 96% (319 statements; test files excluded).
- Combined unique executable source-line coverage: 80.5% (1,485/1,845 lines; tests excluded). Swift: 1,179/1,526 (77.3%); Python: 306/319 (95.9%). Counted Swift archive lines once per source file with `xccov view --archive --json`, plus Python coverage JSON. Xcode does not credit several extension lifecycle lines even though the UI tests execute those surfaces.
- Simulator entitlement outputs for all three targets contain only `group.com.sidequest.shared` as their App Group.
- Light and dark screenshots were visually checked. Local copies are in ignored `build/evidence/sidequest-light.png` and `sidequest-dark.png`.
- The private credential file has mode `0600`; no OpenAI key prefix exists in tracked files or this milestone's commit history.

## Reproduce

```sh
python3 backend/server.py
bash scripts/xcode.sh test
python3 -m coverage run --source=backend -m unittest discover -s backend
python3 -m coverage report --omit='backend/test_*'
```

Use iPhone 17 Pro Simulator with its existing conversation. Set a fresh simulated location before the location UI test (a running simulated route keeps samples fresh during a long suite). Export the existing `DemoScreenshotFactory`'s three screenshots (see the previous milestone evidence) and add them to Photos for the two OCR UI paths. Missing screenshot fixtures skip those integration paths. Nothing sends a message or saves a calendar event automatically.

## Limits

Physical devices still need an Apple team, provisioning for all three bundle IDs, the shared App Group, and a reachable HTTPS API. MapKit resolves real places but does not verify the proposed price, opening hours, or booking availability. OCR grouping/sender detection remains a reviewable heuristic. Pending extracted text remains in the App Group until reviewed or discarded; original images are never persisted by the extension.
