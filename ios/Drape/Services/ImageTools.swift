import UIKit
import Vision
import CoreImage
import ImageIO

struct LocalPhotoResult: Sendable {
    let cutout: Data?
    let labelText: String
}

enum ImageTools {
    // Decode to a bounded pixel size before rendering, avoiding full-resolution camera allocations.
    static func normalized(_ data: Data, maxDimension: Int = 1800) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension
              ] as CFDictionary) else { throw PhotoError.unreadable }
        guard let result = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.88) else { throw PhotoError.unreadable }
        // Rendering removes EXIF, including GPS, before storage and remote processing.
        return result
    }
    static func thumbnail(_ data: Data) -> Data? { try? normalized(data, maxDimension: 440) }

    static func process(front: Data, label: Data?) async -> LocalPhotoResult {
        await Task.detached(priority: .userInitiated) {
            let cutout = try? removeBackground(front)
            let labelText = label.flatMap { try? recognizeText($0) } ?? ""
            return LocalPhotoResult(cutout: cutout, labelText: labelText)
        }.value
    }
    private static func removeBackground(_ data: Data) throws -> Data {
        let handler = VNImageRequestHandler(data: data)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw PhotoError.noSubject }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
        let subject = CIImage(cvPixelBuffer: buffer)
        let inset = max(subject.extent.width, subject.extent.height) * 0.1
        let bounds = subject.extent.insetBy(dx: -inset, dy: -inset)
        let white = CIImage(color: .white).cropped(to: bounds)
        let image = subject.composited(over: white)
        guard let cgImage = CIContext().createCGImage(image, from: bounds),
              let result = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9) else { throw PhotoError.unreadable }
        return result
    }
    private static func recognizeText(_ data: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(data: data).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

enum PhotoError: LocalizedError {
    case unreadable, noSubject
    var errorDescription: String? {
        switch self {
        case .unreadable: "This photo couldn’t be opened. Choose a different image."
        case .noSubject: "We couldn’t separate the clothing from its background. Your original photo is safe."
        }
    }
}
