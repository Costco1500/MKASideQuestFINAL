# SideQuest

Native iPhone app, Messages extension, and image Share Extension, built with SwiftUI, Vision, CoreLocation, MapKit, EventKit, and a small Python API. No web frontend or third-party Swift packages.

## Run in Xcode

1. Open `SideQuest.xcodeproj` in Xcode 26.3 or newer.
2. Choose **SideQuest** and **iPhone 17 Pro**, then Run. The containing app embeds both extensions.
3. In Simulator, open **Messages → a conversation → + → scroll → SideQuest**.
4. In a Debug Simulator build, SideQuest opens directly into **Recent group chat → Analyze Recent Chat**. Vote Down/Maybe/Pass, then **Set the SideQuest → Open in Apple Maps / Add to Calendar**.
5. **Insert poll into Messages** and **Share winning plan** put cards in the compose field. You press Send yourself.

The **SideQuestMessages** scheme launches Messages directly. The 38-message demo uses the real planning and venue pipeline. The local server enables live LLM plans; offline planning falls back to labeled demo suggestions. MapKit needs network access to resolve a place. Demo votes are local; switch the “Demo voter” picker to simulate the four participants.

### Presenting the demo

**Choose Messages** reveals selection and screenshot controls. **Scan Recent Chat** chooses up to ten images, while **Scan demo screenshots** renders and OCRs the saved **Settings → Demo chat script** (`Name: message` per line). Correct sender names and select Last 10/25/50, All, or Clear. SideQuest never reads or seeds Apple's Messages database.

For the Share Extension, select chat screenshots in **Photos → Share → SideQuest**. It reads each image on-device and saves only extracted messages in the existing App Group. After **Done**, open **Messages → SideQuest → Review Messages**. Reviewing or discarding removes the pending file. Choose **New SideQuest** on the import card if you already have a completed plan.

In the containing app, **Set up my profile → Use My Location** requests location once. In Simulator, set a location with **Features → Location → Custom Location** (Atlanta: 33.7834, -84.3831), or use the clearly labeled Debug-only Atlanta demo button. Manual area entry remains available. MapKit searches around available participants' center and attaches real venue names/addresses. Failed lookups keep generic area plans.

## Shared sessions

```sh
python3 backend/server.py
```

Debug Simulator builds use `http://127.0.0.1:8787` automatically when no server is saved, so **Start SideQuest** works as soon as the server above is running. You can still choose **Use local demo server → Save server** in Settings.

### Group chat on real iPhones

Phones need an HTTPS address they can reach. From the repository root on the Mac hosting SideQuest:

```sh
scripts/serve-group.sh
```

It starts the API (or reuses one already on port 8787), downloads Cloudflare's `cloudflared` into ignored `build/tools/` if needed, and prints a temporary `https://….trycloudflare.com` address. No account is needed, the address changes on every run, and the Mac must stay awake while the group plans. Only the organizer enters it: **Settings → paste → Save server → Test connection**. The invitation card carries the address to everyone else. For an always-on server, run `HOST=0.0.0.0 PORT=… python3 backend/server.py` on any HTTPS host with a persistent disk for `SIDEQUEST_DB`.

Choose the total number of people (including yourself), then **Start SideQuest** inserts an invitation before profile entry. Send it into the group chat. The organizer scans screenshots and reviews the extracted messages. Each person, including the organizer, adds their own profile and availability and taps **Done — share my context**. The app and server block Analyze until every expected person is Done, including people who have not joined yet. Then the organizer analyzes the selection to create three plans inside the app. Members vote; only the organizer finalizes. Joining or updating context clears previous plans and votes so every constraint is reconsidered. Sessions refresh every five seconds while open and also have a Refresh action.

## Best times and opening hours

**Your context → When could you hang out?** defaults to the next 7 days (or pick a window). **Check my Apple Calendar** reads busy blocks only and lists your best times; the group card ranks everyone's shared free time the same way. Ranking favors weeknights around 6–7:30 PM, Friday and Saturday nights, and weekend afternoons, prefers roomier windows, avoids times starting within two hours, and spreads picks across days. The top three slots (each up to four hours, 10 AM–11 PM) become the planner's candidate windows, best first.

After MapKit finds places for each plan, SideQuest looks up listed hours for up to four nearby matches per plan in one OpenStreetMap request, and picks the first one open for the whole plan. If none is known to be open, it takes a place with unknown hours, then a partly open one. Each plan card shows **Open then**, **Closes at…**, **Opens at…**, **Closed at that time**, or **Hours not listed**. **Is it open?** checks any place the group names against a plan or best time. Only place names and map positions are sent to OpenStreetMap. Unsupported hour formats (holidays, seasons, "by appointment") show as not listed rather than guessed.

SQLite stores sessions and votes in `backend/data/sidequest.sqlite`. `SIDEQUEST_DB`, `HOST`, and `PORT` override defaults. Sessions expire after seven days and are pruned on subsequent session requests. Invite tokens authorize joining/viewing; member tokens authorize only that person's changes. Tokens are hashed on the server and member credentials are stored in iOS Keychain.

Set `OPENAI_API_KEY` **only on the backend** to enable AI. This Mac loads private configuration from `~/Library/Application Support/SideQuest/server.json` (owner-only mode `600`, outside the checkout); `SIDEQUEST_CONFIG` can select a private file on another server. Existing environment variables take precedence. Never put credentials in Swift, Xcode settings, or a tracked file. `OPENAI_MODEL` defaults to `gpt-4.1-mini`. The backend makes one structured-output call, retries invalid output at most once, then returns labeled demo plans. Missing credentials automatically use demo suggestions with shared voting still active. A client network failure keeps the shared session and selection available to retry.

## Physical iPhone

Choose your Apple development team for **SideQuest**, **SideQuestMessages**, and **SideQuestShare**, use bundle IDs registered to that team, and configure the same App Group for all three. The default group is `group.com.sidequest.shared`; if renamed, update the entitlements, `QuestPreferences`, and `SharedImportStore` together. Then select the connected iPhone and Run. App Groups share profile/settings; membership tokens stay in each app's Keychain. The Share Extension handoff requires the App Group capability.

The development machine used for this build had no signing identity or connected iPhone. The unsigned Release iPhone build passed; physical installation and cross-device iMessage delivery still require that setup.

## Tests

```sh
bash scripts/xcode.sh test
python3 -m unittest discover -s backend -v
```

The simulator script uses **ad-hoc local signing**, which is required for Keychain tests. It selects the full Xcode toolchain without changing the machine's global `xcode-select` setting. UI tests use the simulator's existing Messages conversation and leave no message sent or calendar event saved. Location integration needs a simulated coordinate; screenshot integration needs three demo screenshot fixtures in Photos. Tests skip the photo paths if those fixtures are absent. Unit tests inject venue results and never make live MapKit calls.

Optional backend coverage: `python3 -m coverage run --source=backend -m unittest discover -s backend` then `python3 -m coverage report --omit='backend/test_*'`.

Use the committed Xcode project directly. The legacy generator predates the Share target; do not regenerate this project. Make target membership changes in Xcode or with small project-file edits. Build artifacts are in ignored `build/`.

## Privacy and limits

- No iMessage history API or scraping. Latest 50 means imported messages only. Demo images are rendered from the saved demo script and scanned by Vision.
- Screenshots and OCR bounding boxes stay on-device. Sender detection and bubble grouping are approximate; review the results before analyzing.
- Reviewed imports stay in memory and are cleared after planning/extension deactivation. The Share Extension temporarily stores extracted text in the App Group until Review or Discard; images are not persisted there. Raw messages are never persisted by the server. Only selected, deduplicated messages are sent, at most 50.
- Calendar data becomes busy intervals immediately; titles, notes, and attendees are not transmitted. Availability and winner selection are deterministic.
- Location is requested once; exact user coordinates stay on-device. Shared profiles send coordinates rounded to two decimals; LLM context contains approximate area only. Age ranges are only activity eligibility constraints. Budget uses everyone's lowest comfortable maximum.
- Apple’s calendar editor requires the user to confirm saving. Google calendars already configured in Apple Calendar work through EventKit; direct Google OAuth is intentionally deferred.
- MapKit confirms a place exists, not its prices, availability, or suitability. Hours come from OpenStreetMap where listed and can be missing or out of date. No bookings or production authentication. An invitation grants access to that session's explicitly shared constraints.

See [Share/location/design milestone evidence](docs/share-location-tdd.md), [TDD evidence](docs/tdd-evidence.md) and [OCR/session milestone evidence](docs/ocr-session-tdd.md). Framework references: [Messages](https://developer.apple.com/documentation/messages/msmessagesappviewcontroller), [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
