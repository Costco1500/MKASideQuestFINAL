import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import SideQuestCore

final class ShareViewController: UIViewController {
    private let model = ShareImportModel()
    private var task: Task<Void, Never>?
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareImportView(model: model) { [weak self] in
            self?.task?.cancel()
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        task = Task { await model.read(providers) }
    }
    deinit { task?.cancel() }
}

@MainActor private final class ShareImportModel: ObservableObject {
    @Published var reading = true
    @Published var progress = 0.0
    @Published var count = 0
    @Published var error = ""
    func read(_ providers: [NSItemProvider]) async {
        defer { reading = false }
        do {
            guard (1...10).contains(providers.count) else { throw CocoaError(.fileReadUnsupportedScheme) }
            var blocks: [OCRTextBlock] = []
            for (index, provider) in providers.enumerated() {
                try Task.checkCancellation()
                let image: UIImage = try await withCheckedThrowingContinuation { continuation in
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceThumbnailMaxPixelSize: 2400
                              ] as CFDictionary) else {
                            continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)); return
                        }
                        continuation.resume(returning: UIImage(cgImage: cgImage))
                    }
                }
                let recognized = try await ChatScreenshotOCRService().recognizeMessages(from: [image])
                blocks.append(contentsOf: recognized.map { block in var ordered = block; ordered.screenshotIndex = index; return ordered })
                progress = Double(index + 1) / Double(providers.count)
            }
            try Task.checkCancellation()
            let names = DemoData.participants().map(\.displayName)
            let messages = ScreenshotMessageParser.parse(blocks, participantNames: names)
            guard !messages.isEmpty else { error = "No readable messages found. Try clearer screenshots."; return }
            try SharedImportStore().saveImportedMessages(messages)
            count = messages.count
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

private struct ShareImportView: View {
    @ObservedObject var model: ShareImportModel
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            QuestBrand()
            if model.reading {
                Text("Reading conversation…").font(.system(.title2, design: .rounded, weight: .bold))
                ProgressView(value: model.progress)
            } else if !model.error.isEmpty {
                Text(model.error).font(.body)
            } else {
                Text("\(model.count) messages found").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Label("Ready for SideQuest", systemImage: "checkmark.circle.fill")
                Text("Open SideQuest in Messages to choose what gets analyzed.")
            }
            Button(model.reading ? "Cancel" : "Done", action: done).buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.questBackground).tint(.questAccent)
    }
}
