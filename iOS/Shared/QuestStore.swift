import SwiftUI
import Security
import PhotosUI
import ImageIO
import SideQuestCore

enum QuestPreferences {
    static var defaults: UserDefaults {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.sidequest.shared") != nil {
            return UserDefaults(suiteName: "group.com.sidequest.shared") ?? .standard
        }
        return .standard
    }
    static var server: String {
        get { defaults.string(forKey: "server") ?? "" }
        set { defaults.set(newValue, forKey: "server") }
    }
    static var profile: Participant {
        get {
            if let data = defaults.data(forKey: "profile"), let value = try? APIJSON.decoder.decode(Participant.self, from: data) { return value }
            return Participant(availability: DemoData.range())
        }
        set { defaults.set(try? APIJSON.encoder.encode(newValue), forKey: "profile") }
    }
    static var demoChatScript: String? {
        get { defaults.string(forKey: "demo-chat-script") }
        set { defaults.set(newValue, forKey: "demo-chat-script") }
    }
}

enum MembershipVault {
    static func key(_ link: SessionLink) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.sidequest.membership",
         kSecAttrAccount as String: link.serverURL.absoluteString + "/" + link.sessionId]
    }
    static func save(_ member: Membership, for link: SessionLink) throws {
        let data = try APIJSON.encoder.encode(member)
        let query = key(link)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PlanningError.invalidResponse }
        } else if status != errSecSuccess { throw PlanningError.invalidResponse }
    }
    static func load(_ link: SessionLink) -> Membership? {
        var query = key(link); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? APIJSON.decoder.decode(Membership.self, from: data)
    }
}

@MainActor final class QuestStore: ObservableObject {
    @Published var session: SideQuestSession?
    @Published var messages: [ImportedMessage] = []
    @Published var isDemo = false
    @Published var busy = false
    @Published var status = ""
    @Published var invitation: SessionLink?
    @Published var demoParticipantID = "alex"
    @Published var membership: Membership?
    @Published var isReading = false
    @Published var pendingImportCount = 0
    /// People in the active Messages conversation; nil outside Messages.
    @Published var chatSize: Int?
    private var readTask: Task<Void, Never>?
    private var readID = UUID()
    private var workTask: Task<Void, Never>?
    private var lifecycleID = UUID()
    private let useLiveServices: Bool
    var venueResolver: VenueResolver?
    init(useLiveServices: Bool = true) {
        self.useLiveServices = useLiveServices
        venueResolver = useLiveServices ? VenueResolver() : nil
    }
    var insert: ((SideQuestSession, SessionLink) -> Void)?
    var expand: (() -> Void)?
    var participantID: String { isDemo ? demoParticipantID : membership?.participantId ?? "" }
    var isOwner: Bool { isDemo || membership?.isOwner == true }
    var canGenerate: Bool {
        isOwner && session?.everyoneReady == true && session?.planOptions.isEmpty == true &&
        !busy && !isReading && !MessageImport.analysisMessages(messages).isEmpty
    }
    var link: SessionLink? {
        if isDemo, let session {
            return SessionLink(sessionId: session.id, inviteToken: String(repeating: "d", count: 43), serverURL: URL(string: "https://demo.sidequest.invalid")!, isDemo: true)
        }
        return invitation
    }
    var api: APIClient? { try? APIClient(baseURL: invitation?.serverURL ?? URL(string: QuestPreferences.server) ?? URL(string: "invalid:")!) }
    func work(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; status = ""
        let started = lifecycleID
        workTask = Task { @MainActor in
            defer { if lifecycleID == started { busy = false } }
            do { try Task.checkCancellation(); try await operation() }
            catch { if lifecycleID == started && !Task.isCancelled { status = error.localizedDescription } }
        }
    }
    private func cancelWork() { lifecycleID = UUID(); workTask?.cancel(); workTask = nil; busy = false }
    func checkPendingImport() {
        pendingImportCount = (try? SharedImportStore().loadImportedMessages().count) ?? 0
    }
    func reviewPendingImport() {
        guard membership == nil || isOwner else { status = "The organizer adds the conversation for this session."; return }
        do {
            var imported = try SharedImportStore().loadImportedMessages()
            guard !imported.isEmpty else { checkPendingImport(); return }
            MessageImport.select(.latest50, in: &imported)
            stopReading(); messages = imported
            try SharedImportStore().clearImportedMessages()
            pendingImportCount = 0; status = "Choose the messages you want to analyze."
        } catch { status = error.localizedDescription }
    }
    func discardPendingImport() {
        do { try SharedImportStore().clearImportedMessages(); pendingImportCount = 0 }
        catch { status = error.localizedDescription }
    }
    func startSession(expectedParticipantCount: Int) {
        guard (1...12).contains(expectedParticipantCount), session == nil else { return }
        expand?()
        work { [self] in
            guard let api else { throw PlanningError.invalidServer }
            let member: Membership = try await api.request("api/sessions", body: ["expectedParticipantCount": expectedParticipantCount])
            try accept(member, server: api.baseURL)
            share()
        }
    }
    func startDemo() {
        cancelWork(); stopReading(); expand?(); isDemo = true; invitation = nil; membership = nil; status = ""
        session = try? SideQuestSession.demo(); session?.planOptions = []; session?.context = nil
        demoParticipantID = "alex"; messages = []
        readChat()
    }
    /// Render the editable demo script into images and use the real Vision pipeline.
    func readChat() {
        guard isDemo else { return }
        importScreenshots(DemoChatScreenshots.images(script: QuestPreferences.demoChatScript))
    }
    func importScreenshots(_ images: [UIImage]) {
        recognize { try await ChatScreenshotOCRService().recognizeMessages(from: images) }
    }
    func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        recognize {
            var blocks: [OCRTextBlock] = []
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2400
                      ] as CFDictionary) else { throw ScreenshotImportError.unreadableImage }
                // Recognize one photo at a time so the extension never retains the whole image batch.
                let recognized = try await ChatScreenshotOCRService().recognizeMessages(from: [UIImage(cgImage: image)])
                blocks.append(contentsOf: recognized.map { block in
                    var ordered = block; ordered.screenshotIndex = index; return ordered
                })
            }
            return blocks
        }
    }
    private func recognize(_ scan: @escaping () async throws -> [OCRTextBlock]) {
        guard isOwner, !busy else { return }
        stopReading(); status = ""; isReading = true
        let scanID = readID
        let names = session?.participants.map(\.displayName) ?? []
        readTask = Task { @MainActor [weak self] in
            do {
                let blocks = try await scan()
                try Task.checkCancellation()
                guard let self, self.readID == scanID else { return }
                let extracted = ScreenshotMessageParser.parse(blocks, participantNames: names)
                self.messages = extracted
                self.status = extracted.isEmpty ? "No readable messages found. Try a clearer screenshot." : "Found \(extracted.count) messages. Check the text and senders before analyzing."
                self.isReading = false
            } catch {
                guard !Task.isCancelled, let self, self.readID == scanID else { return }
                self.isReading = false
                self.status = "Could not read these screenshots. Try selecting clearer images."
            }
        }
    }
    func stopReading() { readTask?.cancel(); readTask = nil; readID = UUID(); isReading = false }
    func accept(_ member: Membership, server: URL) throws {
        try Task.checkCancellation()
        let link = SessionLink(sessionId: member.session.id, inviteToken: member.inviteToken, serverURL: server, isDemo: false)
        try MembershipVault.save(member, for: link)
        membership = member; invitation = link; session = member.session; isDemo = false
    }
    func saveProfile(_ profile: Participant) {
        QuestPreferences.profile = profile
        work { [self] in
            guard let api else { throw PlanningError.invalidServer }
            if let session, let membership {
                let updated: SideQuestSession = try await api.request("api/sessions/\(session.id)/context", body: ParticipantBody(profile), token: membership.memberToken)
                apply(updated)
            } else if let invitation {
                let member: Membership = try await api.request("api/sessions/\(invitation.sessionId)/join", body: ParticipantBody(profile), token: invitation.inviteToken)
                try accept(member, server: api.baseURL)
            } else { status = "Start a session before sharing your profile." }
        }
    }
    func apply(_ updated: SideQuestSession) {
        guard !Task.isCancelled,
              session == nil || session?.id == updated.id,
              invitation == nil || invitation?.sessionId == updated.id,
              session == nil || updated.revision >= session!.revision else { return }
        session = updated
        if var member = membership, let link {
            member.session = updated; membership = member; try? MembershipVault.save(member, for: link)
        }
    }
    func refresh(silent: Bool = false) async {
        guard !isDemo, let invitation, let api else { return }
        let started = lifecycleID
        do {
            let latest: SideQuestSession = try await api.request("api/sessions/\(invitation.sessionId)", method: "GET", body: [String: String](), token: membership?.memberToken ?? invitation.inviteToken)
            guard started == lifecycleID else { return }
            apply(latest)
        } catch { if !silent && started == lifecycleID && !Task.isCancelled { status = "Could not refresh the shared session. Check your connection." } }
    }
    func open(_ url: URL) {
        guard let incoming = try? SessionLink.decode(url) else { status = "This is not a valid SideQuest invitation."; return }
        cancelWork(); stopReading(); messages = []; status = ""; invitation = incoming; expand?(); isDemo = incoming.isDemo
        if incoming.isDemo {
            let data = QuestPreferences.defaults.data(forKey: "demo-" + incoming.sessionId)
            session = data.flatMap { try? APIJSON.decoder.decode(SideQuestSession.self, from: $0) } ?? (try? SideQuestSession.demo())
            session?.id = incoming.sessionId; membership = nil
        } else {
            membership = MembershipVault.load(incoming); session = membership?.session
            if membership != nil { Task { await refresh() } }
        }
    }
    func generate() {
        guard canGenerate else {
            if session?.everyoneReady != true { status = "Waiting for everyone to tap Done on their profile." }
            return
        }
        work { [self] in
            if !isDemo { await refresh() }
            try Task.checkCancellation()
            guard var current = session, current.everyoneReady else {
                status = "Waiting for everyone to tap Done on their profile."; return
            }
            let request = PlanningRequest(participants: current.participants, messages: messages)
            guard !request.candidateTimeWindows.isEmpty else { throw PlanningError.noAvailability }
            if !isDemo {
                guard let api, let membership else { throw PlanningError.invalidServer }
                let updated: SideQuestSession = try await api.request("api/sessions/\(current.id)/plan", body: SessionPlanBody(request), token: membership.memberToken)
                guard PlanRules.validate(updated.planOptions, for: request) else { throw PlanningError.invalidResponse }
                try Task.checkCancellation()
                let plans = await ground(updated.planOptions, participants: updated.participants)
                try Task.checkCancellation()
                var resolved = updated
                if plans.contains(where: { $0.venue != nil }) {
                    do {
                        resolved = try await api.request("api/sessions/\(current.id)/venues", body: SessionVenueBody(revision: updated.revision, plans: plans), token: membership.memberToken)
                    } catch {
                        status = "Plans are ready. Place details could not sync; refresh and try again."
                    }
                }
                try Task.checkCancellation()
                apply(resolved); messages = []; return
            }
            var remote: ((PlanningRequest) async throws -> PlanResponse)?
            if useLiveServices {
                var server = QuestPreferences.server
                #if DEBUG && targetEnvironment(simulator)
                if server.isEmpty { server = "http://127.0.0.1:8787" }
                #endif
                if let url = URL(string: server), let client = try? APIClient(baseURL: url) {
                    remote = { try await client.plan($0) }
                }
            }
            let result = try await PlanGenerator.generate(request, remote: remote)
            try Task.checkCancellation()
            current.planOptions = await ground(result.plans, participants: current.participants)
            try Task.checkCancellation()
            current.source = result.source
            var minimized = request; minimized.selectedMessages = []
            current.context = minimized; session = current; messages = []; persistDemo()
        }
    }
    private func ground(_ plans: [PlanOption], participants: [Participant]) async -> [PlanOption] {
        guard let venueResolver else { return plans }
        var people = participants
        if let index = people.firstIndex(where: { $0.id == participantID }), let exact = QuestPreferences.profile.location {
            people[index].location = exact
        }
        return await venueResolver.resolve(plans, participants: people)
    }
    func vote(_ plan: PlanOption, value: VoteValue) {
        guard var current = session else { return }
        if isDemo {
            current.votes.removeAll { $0.participantId == participantID && $0.planId == plan.id }
            current.votes.append(Vote(participantId: participantID, planId: plan.id, value: value)); session = current; persistDemo()
        } else {
            work { [self] in
                guard let api, let membership else { return }
                let updated: SideQuestSession = try await api.request("api/sessions/\(current.id)/vote", body: VoteBody(planId: plan.id, value: value), token: membership.memberToken)
                apply(updated)
            }
        }
    }
    func finalize() {
        guard var current = session else { return }
        if isDemo { current.winningPlanId = VoteEngine.winner(in: current)?.id; session = current; persistDemo() }
        else {
            work { [self] in
                guard let api, let membership else { return }
                let updated: SideQuestSession = try await api.request("api/sessions/\(current.id)/finalize", body: [String: String](), token: membership.memberToken)
                apply(updated)
            }
        }
    }
    func share() {
        guard let session, let link else { return }
        persistDemo()
        if let insert { insert(session, link) } else { status = "Open SideQuest in Messages to insert this card." }
    }
    func persistDemo() {
        if isDemo, let session { QuestPreferences.defaults.set(try? APIJSON.encoder.encode(session), forKey: "demo-" + session.id) }
    }
    func reset() { cancelWork(); stopReading(); session = nil; membership = nil; invitation = nil; messages = []; status = ""; isDemo = false }
}

private enum ScreenshotImportError: Error { case unreadableImage }
