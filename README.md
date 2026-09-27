# SideQuest — A New Way to Plan

A native SwiftUI + iMessage prototype that turns “we should hang out” into a plan. This iMessage extension analyzes group conversations, curated suggestions, and user votes to plan group events that could be exported to the Calendar app.

## Use and Functionality

1. Open SideQuest.xcodeproj. Run **SideQuest** on **iPhone 17 Pro**, or use the **SideQuestMessages** scheme.
2. In Simulator, open a Messages conversation → **+ → SideQuest**. The demo chat opens immediately. The standalone app has the same walkthrough.
3. **Analyze Recent Chat → Show 3 plans**. Open **Why it works for your friends**.
4. Vote **Down** on **Clay & Boba**, then **Simulate group votes**. The existing vote engine chooses the winner; different votes can change it.
5. Open Maps, return, add the plan to Calendar, or **Share Final Plan** to insert a Messages draft. You confirm Save and Send yourself.

**No server, API key, screenshots, photo setup, or second device is needed.** Analysis takes 1.8 seconds and group votes arrive in 1.4 seconds. Tap **… → Reset Demo** in Debug builds to record again. The discreet **Offline prototype** label explains what is simulated.

Dates use the next Thursday. Participant profiles are already filled in. Each plan names a real place near Georgia Tech and Midtown, with the street address Apple Maps listed in September 2026: **Glaze Tea** (960 Spring St NW), **Piedmont Park** (1320 Monroe Dr NE), and **Atlanta Contemporary** (535 Means St NW, free and open until 8 PM Thursdays), then **Insomnia Cookies** (930 Spring St NW). Nothing is booked. Plans appear without any place lookup; Maps opens the business's own page when it loads within three seconds, otherwise a pin at the address. Apple's Maps app may need internet to load its map. The places live in `DemoVenues` in `iOS/Core/Planning.swift`.
