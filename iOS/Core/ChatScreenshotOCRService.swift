import UIKit
import Vision
import ImageIO

public struct OCRTextBlock: Equatable, Sendable {
    public var text: String
    /// Vision coordinates: normalized, with the origin at the lower-left corner.
    public var boundingBox: CGRect
    public var screenshotIndex: Int

    public init(text: String, boundingBox: CGRect, screenshotIndex: Int) {
        self.text = text; self.boundingBox = boundingBox; self.screenshotIndex = screenshotIndex
    }
}

public struct ChatScreenshotOCRService {
    public init() {}

    public func recognizeMessages(from images: [UIImage]) async throws -> [OCRTextBlock] {
        var blocks: [OCRTextBlock] = []
        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            let recognized: [OCRTextBlock] = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        guard let cgImage = image.cgImage else { throw OCRError.unreadableImage }
                        let request = VNRecognizeTextRequest()
                        request.recognitionLevel = .accurate
                        request.usesLanguageCorrection = true
                        let handler = VNImageRequestHandler(cgImage: cgImage,
                                                            orientation: image.imageOrientation.visionOrientation)
                        try handler.perform([request])
                        let result = (request.results ?? []).compactMap { observation -> OCRTextBlock? in
                            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                            return OCRTextBlock(text: text, boundingBox: observation.boundingBox, screenshotIndex: index)
                        }
                        continuation.resume(returning: result)
                    } catch { continuation.resume(throwing: error) }
                }
            }
            try Task.checkCancellation()
            blocks.append(contentsOf: recognized)
        }
        return blocks
    }

    private enum OCRError: LocalizedError {
        case unreadableImage
        var errorDescription: String? { "A selected image could not be read. Try choosing the screenshot again." }
    }
}

private extension UIImage.Orientation {
    var visionOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

/// Simulator fixtures are rendered to images and then pass through the same Vision OCR as picked photos.
public enum DemoChatScreenshots {
    public static func images(script: String? = nil) -> [UIImage] {
        let messages = Array(DemoData.chatScript(script).suffix(50))
        return (0..<3).map { index in
            let start = max(0, index * messages.count / 3 - (index > 0 ? 1 : 0))
            let end = max(start + 1, (index + 1) * messages.count / 3)
            let visible = Array(messages[start..<min(end, messages.count)])
            return render(visible, startIndex: start)
        }
    }

    private static func render(_ messages: [ImportedMessage], startIndex: Int) -> UIImage {
        let width: CGFloat = 900
        let font = UIFont.systemFont(ofSize: 32)
        let bodyWidth: CGFloat = 610
        let rowHeights = messages.map { message in
            let bounds = (message.text as NSString).boundingRect(
                with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
            return max(160, ceil(bounds.height) + 116)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: max(700, rowHeights.reduce(100, +))),
                                       format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: width, height: max(700, rowHeights.reduce(100, +))))
            var y: CGFloat = 45
            for (index, message) in messages.enumerated() {
                let outgoing = (startIndex + index) % 2 == 1
                let x: CGFloat = outgoing ? 195 : 45
                let bubbleHeight = rowHeights[index] - 66
                (message.sender as NSString).draw(at: CGPoint(x: x + 24, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 26, weight: .medium),
                                     .foregroundColor: UIColor.darkGray])
                let bubble = CGRect(x: x, y: y + 38, width: 660, height: bubbleHeight)
                (outgoing ? UIColor(red: 0.02, green: 0.4, blue: 0.9, alpha: 1) : UIColor(white: 0.91, alpha: 1)).setFill()
                UIBezierPath(roundedRect: bubble, cornerRadius: 28).fill()
                (message.text as NSString).draw(with: CGRect(x: x + 24, y: y + 58, width: bodyWidth, height: bubbleHeight - 30),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font, .foregroundColor: outgoing ? UIColor.white : UIColor.black], context: nil)
                y += rowHeights[index]
            }
        }
    }
}
