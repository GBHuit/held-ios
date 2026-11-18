import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Original image bytes retained only after the user completes OCR review.
struct OCRReviewedImage {
    let data: Data
    let filename: String
    let mimeType: String

    init(data: Data, pageNumber: Int) {
        self.data = data
        var pathExtension = "img"
        var mimeType = "application/octet-stream"
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let identifier = CGImageSourceGetType(source) as String?,
           let type = UTType(identifier) {
            pathExtension = type.preferredFilenameExtension ?? pathExtension
            mimeType = type.preferredMIMEType ?? mimeType
        }
        self.filename = "OCR receipt page \(pageNumber).\(pathExtension)"
        self.mimeType = mimeType
    }
}
