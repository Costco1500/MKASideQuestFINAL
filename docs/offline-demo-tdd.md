# Offline demo milestone

Source: the supplied demo-only hackathon brief, September 26, 2026.

| Guarantee | Evidence |
|---|---|
| Opens into 38 fictional messages with no setup | OfflineDemoTests.testLaunchAndResetNeedNoSetup |
| Three curated plans satisfy budget, age, and availability constraints | testExactlyThreeOfflinePlansExplainEveryFriendAndMeetConstraints |
| Simulated friends vote deterministically; Alex's vote can change the winner | testGroupVotesAreDeterministicAndUseVoteEngine |
| Reset cancels analysis and restores chat, empty plans, and empty votes | testResetCancelsInFlightAnalysis |
| Maps return restores the winner; sharing requires an explicit action | testWinningDemoResumesAfterMapsAndInsertsOnlyOnRequest |
| Messages is embedded, Share Extension is absent | ShellTests |

RED: f067e5c compiled the new tests against the previous store and failed on the missing offline stages/actions. GREEN: 2500016 passed all 20 focused native tests. The README contains the exact validation command.

The previous local server was stopped before UI verification. No backend tests, OCR workflows, or live model calls were used. The app's reachable store has no networking client. Maps is an explicit handoff to Apple's app; no lookup is needed to generate plans. Sample meetup coordinates are labeled as demo data.

The Release iPhone build passed without signing. Xcode lists SideQuest, SideQuestMessages, and the core/test targets; no Share target or scheme remains. Old source files and unrelated deterministic tests are retained without maintaining the removed live experience.

Final verification: **20 focused unit tests + 2 UI walkthroughs passed** on iPhone 17 Pro / iOS 26.3. The app test covers disclosure, chat, insights, personalized plan explanations, voting, Calendar, and reset. The Messages test covers the same story plus the real Maps round trip, Calendar editor, and final MSMessage draft. Calendar was canceled and the draft removed without sending.

Xcode line coverage across nine demo flow files is 596/709 (84.1%); QuestStore is 119/119 and QuestFlowView is 267/271. Extension lifecycle coverage is not collected by this runner; its native handoffs were verified by the Messages UI test. Light and dark conversation screens were visually checked.

Local result: build/DerivedData/Logs/Test/Test-SideQuest-2026.09.26_19-54-57--0400.xcresult. It includes screenshots for chat, understanding, plan explanations, winner, Maps, Calendar, and the message draft. Branded app and Messages icons reuse the existing sunset colors and sparkle mark.
