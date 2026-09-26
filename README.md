# SideQuest

Native iPhone app + Messages extension, built with SwiftUI, Messages, EventKit, and a small Python API. No web frontend or third-party Swift packages.

## Run in Xcode

1. Open `SideQuest.xcodeproj` in Xcode 26.3 or newer.
2. Choose **SideQuest** and **iPhone 17 Pro**, then Run. The containing app embeds the Messages extension.
3. In Simulator, open **Messages → a conversation → + → scroll → SideQuest**.
4. Tap **Try Demo → Read this chat → Analyze 8 selected messages**. Vote Down/Maybe/Pass, then **Set the SideQuest → Add to Calendar**.
5. **Insert poll into Messages** and **Share winning plan** put cards in the compose field. You press Send yourself.

The **SideQuestMessages** scheme launches Messages directly. Try Demo uses the same screens as shared sessions and needs no network, account, or API key. Demo votes are local; switch the “Demo voter” picker to simulate the four participants.

### Presenting the demo

Apple does not let Messages extensions read a conversation, so in demo mode **Read this chat** is simulated: it reveals a scripted conversation one message at a time. Edit the script in **Settings → Demo chat script** (one `Name: message` per line, using Alex, Maya, Jake and Sarah so plans and votes line up), then send those same messages in the group chat you present. The containing app labels the button **Load demo chat**. Planning, voting, availability and calendar steps are the real implementation.

## Shared sessions

```sh
python3 backend/server.py
```

In SideQuest's Settings, choose **Use local demo server → Save server** for the simulator. For physical iPhones, run this API behind HTTPS and enter its public HTTPS base URL. This repository does not deploy a public server.

Start SideQuest, submit your own profile, and insert the invitation card. Each friend opens the card and contributes their own context. The organizer refreshes, imports/selects conversation text, and generates plans. Members vote; only the organizer finalizes. Joining or updating context clears previous plans and votes so every constraint is reconsidered. Sessions refresh every five seconds while open and also have a Refresh action.

SQLite stores sessions and votes in `backend/data/sidequest.sqlite`. `SIDEQUEST_DB`, `HOST`, and `PORT` override defaults. Sessions expire after seven days and are pruned on subsequent session requests. Invite tokens authorize joining/viewing; member tokens authorize only that person's changes. Tokens are hashed on the server and member credentials are stored in iOS Keychain.

Set `OPENAI_API_KEY` **only on the backend** to enable AI; `OPENAI_MODEL` defaults to `gpt-4.1-mini`. The backend makes one structured-output call, retries invalid output at most once, then returns labeled demo plans. Missing credentials automatically use demo suggestions with shared voting still active. Client network failure during planning switches to a clearly labeled local demo.

## Physical iPhone

Choose your Apple development team for **SideQuest** and **SideQuestMessages**, use bundle IDs registered to that team, and configure the same App Group for both. The default group is `group.com.sidequest.shared`; if renamed, update the entitlements and `QuestPreferences` together. Then select the connected iPhone and Run. App Groups share profile/settings; membership tokens stay in each app's Keychain. If App Groups are unavailable, remove that capability and configure the profile/server separately inside Messages.

The development machine used for this build had no signing identity or connected iPhone. The unsigned Release iPhone build passed; physical installation and cross-device iMessage delivery still require that setup.

## Tests

```sh
bash scripts/xcode.sh test
python3 -m unittest discover -s backend -v
```

The simulator script uses **ad-hoc local signing**, which is required for Keychain tests. It selects the full Xcode toolchain without changing the machine's global `xcode-select` setting. UI tests use the simulator's seeded Messages conversation and leave no message sent or calendar event saved.

Optional backend coverage: `python3 -m coverage run --source=backend -m unittest discover -s backend` then `python3 -m coverage report --omit='backend/test_*'`.

The committed Xcode project runs without generation tools. After adding source files, `ruby scripts/generate_project.rb` updates it (requires the `xcodeproj` gem). Build artifacts are in ignored `build/`.

## Privacy and limits

- No iMessage history API or scraping. Latest 50 means imported messages only. The demo's “Read this chat” shows the saved demo script, not Messages content.
- Raw imports stay in memory, are cleared after planning/extension deactivation, and are never persisted by the server. Only selected, deduplicated messages are sent, at most 50.
- Calendar data becomes busy intervals immediately; titles, notes, and attendees are not transmitted. Availability and winner selection are deterministic.
- Location is entered as an approximate area; no GPS tracking. Age ranges are only activity eligibility constraints. Budget uses everyone's lowest comfortable maximum.
- Apple’s calendar editor requires the user to confirm saving. Google calendars already configured in Apple Calendar work through EventKit; direct Google OAuth is intentionally deferred.
- No confirmed venue availability, bookings, or production authentication. An invitation grants access to that session's explicitly shared constraints.

See [TDD evidence](docs/tdd-evidence.md). Framework references: [Messages](https://developer.apple.com/documentation/messages/msmessagesappviewcontroller), [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
