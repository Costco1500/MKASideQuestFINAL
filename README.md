# SideQuest — offline hackathon demo

A native SwiftUI + iMessage prototype: turn “we should hang out” into a plan. This build uses a fictional group conversation, curated suggestions, and simulated votes. **It makes no backend or LLM calls.** Calendar and Messages actions are real.

## Run and record

1. Open SideQuest.xcodeproj. Run **SideQuest** on **iPhone 17 Pro**, or use the **SideQuestMessages** scheme.
2. In Simulator, open a Messages conversation → **+ → SideQuest**. The demo chat opens immediately. The standalone app has the same walkthrough.
3. **Analyze Recent Chat → Show 3 plans**. Open **Why it works for your friends**.
4. Vote **Down** on **Clay & Boba**, then **Simulate group votes**. The existing vote engine chooses the winner; different votes can change it.
5. Open Maps, return, add the plan to Calendar, or **Share Final Plan** to insert a Messages draft. You confirm Save and Send yourself.

**No server, API key, screenshots, photo setup, or second device is needed.** Analysis takes 1.8 seconds and group votes arrive in 1.4 seconds. Tap **… → Reset Demo** in Debug builds to record again. The discreet **Offline prototype** label explains what is simulated.

Dates use the next Thursday. Participant profiles are already filled in. Maps opens a clearly labeled sample meetup point in Midtown Atlanta; it is not a booked or verified activity venue. The demo never waits for a place lookup. Apple's Maps app may need internet to load its map.

## Validation

    bash scripts/xcode.sh test \
      -only-testing:SideQuestTests/OfflineDemoTests \
      -only-testing:SideQuestTests/WarmDemoTests \
      -only-testing:SideQuestTests/ShellTests \
      -only-testing:SideQuestTests/PlanningTests \
      -only-testing:SideQuestTests/SessionTests \
      -only-testing:SideQuestUITests

Use the committed Xcode project; do not run the legacy project generator. The app embeds only the Messages extension. Older backend/import sources remain archived on disk and are outside this demo's user experience. Physical-device installation still requires Apple signing.

[TDD evidence](docs/offline-demo-tdd.md).
