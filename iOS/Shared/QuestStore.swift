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
    /// People in the active Messages conversation; nil outside Messages.
    @Published var chatSize: Int?
    private var readTask: Task<Void, Never>?
    private var readID = UUID()
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
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { status = error.localizedDescription }
        }
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
        stopReading(); expand?(); isDemo = true; invitation = nil; membership = nil; status = ""
        session = try? SideQuestSession.demo(); session?.planOptions = []; session?.context = nil
        demoParticipantID = "alex"; messages = []
        readChat()
    }
    /// Render the editable demo script into images and use the real Vision pipeline.
    func readChat() {
        guard isDemo else { return }
        importScreenshots(DemoChatScreenshots.images(script: QuestPreferences.demoChatScript))
    }
    func importScreenshots(_ images: [UIImage]) { recognize { images } }
    func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        recognize {
            var images: [UIImage] = []
            for item in items {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2400
                      ] as CFDictionary) else { throw ScreenshotImportError.unreadableImage }
                images.append(UIImage(cgImage: image))
            }
            return images
        }
    }
    private func recognize(_ load: @escaping () async throws -> [UIImage]) {
        guard isOwner, !busy else { return }
        stopReading(); status = ""; isReading = true
        let scanID = readID
        let names = session?.participants.map(\.displayName) ?? []
        readTask = Task { @MainActor [weak self] in
            do {
                let images = try await load()
                let blocks = try await ChatScreenshotOCRService().recognizeMessages(from: images)
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
        guard session == nil || updated.revision >= session!.revision else { return }
        session = updated
        if var member = membership, let link {
            member.session = updated; membership = member; try? MembershipVault.save(member, for: link)
        }
    }
    func refresh(silent: Bool = false) async {
        guard !isDemo, let invitation, let api else { return }
        do {
            let latest: SideQuestSession = try await api.request("api/sessions/\(invitation.sessionId)", method: "GET", body: [String: String](), token: membership?.memberToken ?? invitation.inviteToken)
            apply(latest)
        } catch { if !silent { status = "Could not refresh the shared session. Check your connection." } }
    }
    func open(_ url: URL) {
        guard let incoming = try? SessionLink.decode(url) else { status = "This is not a valid SideQuest invitation."; return }
        stopReading(); messages = []; status = ""; invitation = incoming; expand?(); isDemo = incoming.isDemo
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
            guard var current = session, current.everyoneReady else {
                status = "Waiting for everyone to tap Done on their profile."; return
            }
            let request = PlanningRequest(participants: current.participants, messages: messages)
            guard !request.candidateTimeWindows.isEmpty else { throw PlanningError.noAvailability }
            if !isDemo {
                guard let api, let membership else { throw PlanningError.invalidServer }
                let updated: SideQuestSession = try await api.request("api/sessions/\(current.id)/plan", body: SessionPlanBody(request), token: membership.memberToken)
                guard PlanRules.validate(updated.planOptions, for: request) else { throw PlanningError.invalidResponse }
                apply(updated); messages = []; return
            }
            let result = try await PlanGenerator.generate(request)
            current.planOptions = result.plans; current.source = result.source
            var minimized = request; minimized.selectedMessages = []
            current.context = minimized; session = current; messages = []; persistDemo()
        }
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
    func reset() { stopReading(); session = nil; membership = nil; invitation = nil; messages = []; status = ""; isDemo = false }
}

private enum ScreenshotImportError: Error { case unreadableImage }
